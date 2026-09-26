"""
Perspective Correction and Page Rectification Module.
Detects page document boundaries from photographs, estimates 4 corner points,
applies perspective transformation to a normalized top-down plane,
and normalizes reading orientation with safe fallbacks.
"""

import cv2
import numpy as np
from typing import Tuple, Optional, Dict, Any, Callable


def order_quad_points(pts: np.ndarray) -> np.ndarray:
    """
    Orders 4 coordinates consistently:
    0: Top-Left (TL)
    1: Top-Right (TR)
    2: Bottom-Right (BR)
    3: Bottom-Left (BL)
    """
    pts = pts.reshape((4, 2)).astype("float32")
    rect = np.zeros((4, 2), dtype="float32")

    # Sum of coordinates: top-left has smallest sum, bottom-right has largest sum
    s = pts.sum(axis=1)
    rect[0] = pts[np.argmin(s)]
    rect[2] = pts[np.argmax(s)]

    # Difference (x - y): top-right has smallest diff, bottom-left has largest
    diff = pts[:, 0] - pts[:, 1]
    rect[1] = pts[np.argmax(diff)]
    rect[3] = pts[np.argmin(diff)]

    return rect


def detect_page_corners(
    image: np.ndarray,
    min_area_ratio: float = 0.25
) -> Optional[np.ndarray]:
    """
    Locates 4-corner document polygon in photographed page.
    Combines:
    1. HSV paper brightness masking (isolates white/cream paper from desk/bezel)
    2. Edge-based Canny contour detection with bilateral pre-filtering
    Returns ordered 4-point numpy array [[TL], [TR], [BR], [BL]] or None if not found.
    """
    h, w = image.shape[:2]
    total_area = float(h * w)

    # Strategy 1: Brightness mask contour (effective for paper on desk)
    if len(image.shape) == 3:
        hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
        v_channel = hsv[:, :, 2]
        _, paper_thresh = cv2.threshold(v_channel, 130, 255, cv2.THRESH_BINARY)
        close_k = cv2.getStructuringElement(cv2.MORPH_RECT, (25, 25))
        closed_paper = cv2.morphologyEx(paper_thresh, cv2.MORPH_CLOSE, close_k, iterations=2)
        cnts, _ = cv2.findContours(closed_paper, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        if cnts:
            largest = max(cnts, key=cv2.contourArea)
            area = cv2.contourArea(largest)
            if area >= total_area * min_area_ratio:
                peri = cv2.arcLength(largest, True)
                approx = cv2.approxPolyDP(largest, 0.03 * peri, True)
                if len(approx) == 4 and cv2.isContourConvex(approx):
                    return order_quad_points(approx)

    # Strategy 2: Canny edge contour detection
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if len(image.shape) == 3 else image.copy()
    blurred = cv2.bilateralFilter(gray, 9, 75, 75)

    for canny_lo, canny_hi, close_size, eps in [
        (40, 150, 5, 0.025),
        (20, 80, 15, 0.040)
    ]:
        edges = cv2.Canny(blurred, canny_lo, canny_hi)
        k = cv2.getStructuringElement(cv2.MORPH_RECT, (close_size, close_size))
        closed = cv2.morphologyEx(edges, cv2.MORPH_CLOSE, k, iterations=2)
        cnts, _ = cv2.findContours(closed, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        cnts = sorted(cnts, key=cv2.contourArea, reverse=True)[:6]
        for c in cnts:
            area = cv2.contourArea(c)
            if area < total_area * min_area_ratio:
                continue
            peri = cv2.arcLength(c, True)
            approx = cv2.approxPolyDP(c, eps * peri, True)
            if len(approx) == 4 and cv2.isContourConvex(approx):
                return order_quad_points(approx)

    return None


def rectify_page_perspective(
    image: np.ndarray,
    corners: Optional[np.ndarray] = None
) -> Tuple[np.ndarray, np.ndarray, bool]:
    """
    Applies perspective transformation to rectify document to a flat top-down view.
    If corners is None, attempts automatic detection with detect_page_corners().
    If corners cannot be found, falls back safely to identity transform without modifying original.

    Returns: (rectified_image, transform_matrix, was_rectified)
    """
    h, w = image.shape[:2]

    if corners is None:
        corners = detect_page_corners(image)

    if corners is None:
        # Fallback path: identity transform
        identity_m = np.eye(3, dtype=np.float32)
        return image.copy(), identity_m, False

    rect = order_quad_points(corners)
    (tl, tr, br, bl) = rect

    # Compute width of new image
    width_a = np.sqrt(((br[0] - bl[0]) ** 2) + ((br[1] - bl[1]) ** 2))
    width_b = np.sqrt(((tr[0] - tl[0]) ** 2) + ((tr[1] - tl[1]) ** 2))
    max_w = max(int(round(width_a)), int(round(width_b)))

    # Compute height of new image
    height_a = np.sqrt(((tr[0] - br[0]) ** 2) + ((tr[1] - br[1]) ** 2))
    height_b = np.sqrt(((tl[0] - bl[0]) ** 2) + ((tl[1] - bl[1]) ** 2))
    max_h = max(int(round(height_a)), int(round(height_b)))

    # Prevent collapsing to tiny sub-windows
    if max_w < w * 0.35 or max_h < h * 0.35:
        identity_m = np.eye(3, dtype=np.float32)
        return image.copy(), identity_m, False

    dst = np.array([
        [0, 0],
        [max_w - 1, 0],
        [max_w - 1, max_h - 1],
        [0, max_h - 1]
    ], dtype="float32")

    transform_m = cv2.getPerspectiveTransform(rect, dst)
    rectified = cv2.warpPerspective(image, transform_m, (max_w, max_h), flags=cv2.INTER_LINEAR)

    return rectified, transform_m, True


def normalize_orientation(
    image: np.ndarray,
    scorer_fn: Optional[Callable[[np.ndarray], float]] = None
) -> Tuple[int, np.ndarray, Dict[str, Any]]:
    """
    Evaluates 4 candidate rotations (0°, 90°, 180°, 270°) and normalizes upright orientation.
    Uses shadow gradient dipole vectors and/or candidate Braille distribution scorer function.
    Returns: (best_rotation_degrees, upright_image, metrics_dict)
    """
    rotations = [0, 90, 180, 270]
    scores = {}

    for angle in rotations:
        if angle == 0:
            rot_img = image.copy()
        elif angle == 90:
            rot_img = cv2.rotate(image, cv2.ROTATE_90_CLOCKWISE)
        elif angle == 180:
            rot_img = cv2.rotate(image, cv2.ROTATE_180)
        elif angle == 270:
            rot_img = cv2.rotate(image, cv2.ROTATE_90_COUNTERCLOCKWISE)

        if scorer_fn is not None:
            try:
                score = scorer_fn(rot_img)
            except Exception:
                score = 0.0
        else:
            # Default heuristic: count horizontal gradient coherence
            gray = cv2.cvtColor(rot_img, cv2.COLOR_BGR2GRAY) if len(rot_img.shape) == 3 else rot_img
            sobel_x = cv2.Sobel(gray, cv2.CV_32F, 1, 0, ksize=3)
            sobel_y = cv2.Sobel(gray, cv2.CV_32F, 0, 1, ksize=3)
            # Braille dots typically produce stronger vertical contrast than horizontal
            score = float(np.mean(np.abs(sobel_y)) - 0.5 * np.mean(np.abs(sobel_x)))

        scores[angle] = score

    best_rot = max(scores.keys(), key=lambda a: scores[a])

    if best_rot == 0:
        upright = image.copy()
    elif best_rot == 90:
        upright = cv2.rotate(image, cv2.ROTATE_90_CLOCKWISE)
    elif best_rot == 180:
        upright = cv2.rotate(image, cv2.ROTATE_180)
    else:
        upright = cv2.rotate(image, cv2.ROTATE_90_COUNTERCLOCKWISE)

    metrics = {
        "best_angle": best_rot,
        "rotation_scores": scores
    }

    return best_rot, upright, metrics
