"""
Preprocessing module for Braille OCR.
Provides:
1. Perspective skew detection and warping (warpPerspective).
2. Paired luminance shadow-highlight gradient analysis for illumination orientation.
3. 2-pass Braille frequency distribution scoring (0°, 90°, 180°, 270°).
4. Automatic orientation detection and correction.
"""

import cv2
import numpy as np
from typing import Tuple, List, Optional, Dict, Any


def order_points(pts: np.ndarray) -> np.ndarray:
    """
    Orders 4 coordinates as:
    0: top-left
    1: top-right
    2: bottom-right
    3: bottom-left
    """
    pts = pts.reshape((4, 2)).astype("float32")
    rect = np.zeros((4, 2), dtype="float32")

    # Sum of coordinates: top-left has smallest sum, bottom-right has largest sum
    s = pts.sum(axis=1)
    rect[0] = pts[np.argmin(s)]
    rect[2] = pts[np.argmax(s)]

    # Difference of coordinates: top-right has smallest difference (x - y), bottom-left has largest
    diff = pts[:, 0] - pts[:, 1]
    rect[1] = pts[np.argmax(diff)]
    rect[3] = pts[np.argmin(diff)]

    return rect


def detect_page_contour(image: np.ndarray, min_area_ratio: float = 0.15) -> Optional[np.ndarray]:
    """
    Locates document or page boundary polygon in the image.
    Returns 4 corner points ordered as [TL, TR, BR, BL], or None if no page quad is found.
    Two-pass strategy: first try tight Canny params, then relax for soft phone-camera borders.
    """
    if len(image.shape) == 3:
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    else:
        gray = image.copy()

    h, w = gray.shape[:2]
    total_area = float(h * w)

    blurred = cv2.bilateralFilter(gray, 9, 75, 75)

    def _try_find_quad(edges_img: np.ndarray, close_ksize: int, close_iter: int, epsilon: float) -> Optional[np.ndarray]:
        kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (close_ksize, close_ksize))
        closed = cv2.morphologyEx(edges_img, cv2.MORPH_CLOSE, kernel, iterations=close_iter)
        cnts, _ = cv2.findContours(closed, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        cnts = sorted(cnts, key=cv2.contourArea, reverse=True)[:8]
        for c in cnts:
            if cv2.contourArea(c) < total_area * min_area_ratio:
                continue
            peri = cv2.arcLength(c, True)
            approx = cv2.approxPolyDP(c, epsilon * peri, True)
            if len(approx) == 4 and cv2.isContourConvex(approx):
                return order_points(approx)
        return None

    # Pass 1: standard tight parameters
    edges1 = cv2.Canny(blurred, 40, 150)
    result = _try_find_quad(edges1, close_ksize=5, close_iter=2, epsilon=0.025)
    if result is not None:
        # Validate: the page quad should cover at least 35% of image area
        quad_area = cv2.contourArea(result)
        if quad_area >= total_area * 0.35:
            return result

    # Pass 2: softer Canny + aggressive closing for phone-camera images with diffuse paper edges
    edges2 = cv2.Canny(blurred, 20, 80)
    result = _try_find_quad(edges2, close_ksize=15, close_iter=3, epsilon=0.04)
    if result is not None:
        quad_area = cv2.contourArea(result)
        if quad_area >= total_area * 0.35:
            return result

    return None


def warp_perspective(image: np.ndarray, pts: Optional[np.ndarray] = None) -> Tuple[np.ndarray, np.ndarray]:
    """
    Applies perspective transformation to rectify document to a flat top-down view.
    If pts is None, attempts to detect page boundary, falling back to full image rectangle.
    Returns (warped_image, transform_matrix).
    """
    h, w = image.shape[:2]

    if pts is None:
        pts = detect_page_contour(image)

    if pts is None:
        # Fallback to standard identity rect
        rect = np.array([
            [0, 0],
            [w - 1, 0],
            [w - 1, h - 1],
            [0, h - 1]
        ], dtype="float32")
        return image.copy(), np.eye(3, dtype="float32")

    rect = order_points(pts)
    (tl, tr, br, bl) = rect

    # Compute width of new image
    width_a = np.linalg.norm(br - bl)
    width_b = np.linalg.norm(tr - tl)
    max_w = max(int(width_a), int(width_b))

    # Compute height of new image
    height_a = np.linalg.norm(tr - br)
    height_b = np.linalg.norm(tl - bl)
    max_h = max(int(height_a), int(height_b))

    # Guard against zero or extreme aspect ratio
    max_w = max(max_w, 64)
    max_h = max(max_h, 64)

    dst = np.array([
        [0, 0],
        [max_w - 1, 0],
        [max_w - 1, max_h - 1],
        [0, max_h - 1]
    ], dtype="float32")

    M = cv2.getPerspectiveTransform(rect, dst)
    warped = cv2.warpPerspective(image, M, (max_w, max_h), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
    return warped, M


def analyze_shadow_gradient(gray_img: np.ndarray, kernel_size: int = 7) -> Dict[str, Any]:
    """
    Analyzes paired luminance extrema (bright crests next to shadow troughs) on embossed paper.
    Computes vector from highlight crest to shadow trough:
    v = (x_shadow - x_crest, y_shadow - y_crest).
    
    Returns:
        {
            'dominant_angle_deg': float (0..360),
            'mean_dx': float,
            'mean_dy': float,
            'pairs_count': int,
            'shadow_below': bool (True if shadow is below crest, indicating standard overhead light)
        }
    """
    if len(gray_img.shape) == 3:
        gray = cv2.cvtColor(gray_img, cv2.COLOR_BGR2GRAY)
    else:
        gray = gray_img

    # Speed optimization: crop central region to avoid edge artifacts and speed up morphology
    h, w = gray.shape[:2]
    if h > 500 or w > 500:
        cy, cx = h // 2, w // 2
        crop_h, crop_w = min(h, 500), min(w, 500)
        gray = gray[cy - crop_h//2 : cy + crop_h//2, cx - crop_w//2 : cx + crop_w//2]

    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (kernel_size, kernel_size))
    tophat = cv2.morphologyEx(gray, cv2.MORPH_TOPHAT, k)
    blackhat = cv2.morphologyEx(gray, cv2.MORPH_BLACKHAT, k)

    # Threshold significant peaks and valleys
    th_crest = max(10, int(np.mean(tophat) + 1.2 * np.std(tophat)))
    th_trough = max(10, int(np.mean(blackhat) + 1.2 * np.std(blackhat)))

    _, bin_crest = cv2.threshold(tophat, th_crest, 255, cv2.THRESH_BINARY)
    _, bin_trough = cv2.threshold(blackhat, th_trough, 255, cv2.THRESH_BINARY)

    # Find centroids
    num_c, _, stats_c, cent_c = cv2.connectedComponentsWithStats(bin_crest)
    num_t, _, stats_t, cent_t = cv2.connectedComponentsWithStats(bin_trough)

    crests = [cent_c[i] for i in range(1, num_c) if 3 <= stats_c[i, cv2.CC_STAT_AREA] <= 150]
    troughs = [cent_t[i] for i in range(1, num_t) if 3 <= stats_t[i, cv2.CC_STAT_AREA] <= 150]

    # Cap crests for instant vector matching
    if len(crests) > 300:
        crests = crests[:300]

    vectors = []
    max_search_dist = kernel_size * 2.5
    min_search_dist = 2.0

    if crests and troughs:
        troughs_arr = np.array(troughs, dtype=np.float32)
        for c in crests:
            dists = np.linalg.norm(troughs_arr - c, axis=1)
            min_idx = np.argmin(dists)
            d = dists[min_idx]
            if min_search_dist <= d <= max_search_dist:
                vec = troughs_arr[min_idx] - c
                vectors.append(vec)

    if vectors:
        vecs = np.array(vectors)
        mean_dx = float(np.mean(vecs[:, 0]))
        mean_dy = float(np.mean(vecs[:, 1]))
        angle_rad = np.arctan2(mean_dy, mean_dx)
        angle_deg = float(np.degrees(angle_rad)) % 360.0
        # Shadow below means y_shadow > y_crest => dy > 0 (angles in (0, 180))
        shadow_below = (mean_dy > 0.3)
        return {
            'dominant_angle_deg': angle_deg,
            'mean_dx': mean_dx,
            'mean_dy': mean_dy,
            'pairs_count': len(vectors),
            'shadow_below': shadow_below
        }

    return {
        'dominant_angle_deg': 90.0,
        'mean_dx': 0.0,
        'mean_dy': 1.0,
        'pairs_count': 0,
        'shadow_below': True
    }


def score_braille_distribution(cell_indices: List[int]) -> float:
    """
    Scores a collection of detected 6-dot Braille cells against English Braille frequency distributions.
    Standard 6-dot cell bit encoding:
      Dot 1: bit 0 (val 1)
      Dot 2: bit 1 (val 2)
      Dot 3: bit 2 (val 4)
      Dot 4: bit 3 (val 8)
      Dot 5: bit 4 (val 16)
      Dot 6: bit 5 (val 32)
      
    Key Linguistic Rules of English Braille:
    1. Upper dots (1, 2, 4, 5) dominate natural letters ('a'-'j' use ONLY upper dots; 'k'-'t' add dot 3).
    2. Lower cells (only dots 2, 3, 5, 6: comma, semicolon, colon, period, question mark, etc.)
       are punctuation and account for < 8% of natural text.
    3. An upside-down (180° inverted) image inverts:
       Dot 1 <-> Dot 6, Dot 2 <-> Dot 5, Dot 3 <-> Dot 4.
       This turns the common upper dots into lower dots, causing 40-70% of cells to look like punctuation!
    """
    if not cell_indices:
        return -100.0

    valid_cells = [c for c in cell_indices if 0 < c < 64]
    if not valid_cells:
        return -100.0

    # Common English Braille letter classes (a, b, c, d, e, f, g, h, i, j, l, m, n, o, p, r, s, t, u, and, the, of, for, with)
    # Binary representation to index:
    # 'a' = 100000 = 32 (or 1 depending on bit convention). In VisionMate:
    # '100000' (Dot 1) = 32
    # '110000' (Dots 1,2) = 48 ('b')
    # '100100' (Dots 1,4) = 36 ('c')
    # '100110' (Dots 1,4,5) = 38 ('d')
    # '100010' (Dots 1,5) = 34 ('e')
    # '110100' (Dots 1,2,4) = 52 ('f')
    # '110110' (Dots 1,2,4,5) = 54 ('g')
    # '110010' (Dots 1,2,5) = 50 ('h')
    # '010100' (Dots 2,4) = 20 ('i')
    # '010110' (Dots 2,4,5) = 22 ('j')
    # '111000' (Dots 1,2,3) = 56 ('l')
    # '101100' (Dots 1,3,4) = 44 ('m')
    # '101110' (Dots 1,3,4,5) = 46 ('n')
    # '101010' (Dots 1,3,5) = 42 ('o')
    # '111100' (Dots 1,2,3,4) = 60 ('p')
    # '111010' (Dots 1,2,3,5) = 58 ('r')
    # '011100' (Dots 2,3,4) = 28 ('s')
    # '011110' (Dots 2,3,4,5) = 30 ('t')
    # '011101' (the) = 29
    # '111101' (and) = 61
    # '111011' (for) = 59
    # '111111' (of) = 63
    # '011111' (with) = 31

    frequent_letters = {
        32, 48, 36, 38, 34, 52, 54, 50, 20, 22,
        40, 56, 44, 46, 42, 60, 62, 58, 28, 30,
        41, 57, 29, 61, 59, 63, 31, 23
    }

    # Punctuation / sparse lower classes (classes without upper dots 1, 4):
    # '000001' (comma) = 1
    # '000010' = 2
    # '000011' (semicolon) = 3
    # '000101' = 5
    # '000111' = 7
    # '001000' (apostrophe) = 8
    # '001001' (hyphen) = 9
    # '001010' (asterisk) = 10
    # '001011' (period) = 11
    # '001100' = 12
    # '001101' = 13
    # '010000' (semicolon) = 16
    # '010001' = 17
    # '010010' (colon) = 18
    # '010011' (period) = 19
    # '011000' (semicolon) = 24
    # '011001' (question) = 25
    # '011010' (exclamation) = 26
    # '011011' (parenthesis) = 27
    lower_punct_classes = {
        1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 18, 19, 24, 25, 26, 27
    }

    n_total = len(valid_cells)
    punct_count = sum(1 for c in valid_cells if c in lower_punct_classes)
    freq_letter_count = sum(1 for c in valid_cells if c in frequent_letters)

    punct_ratio = punct_count / float(n_total)
    freq_letter_ratio = freq_letter_count / float(n_total)

    # Upper dots (dots 1, 2, 4, 5) count vs lower dots (dots 3, 6)
    upper_dot_count = 0
    lower_dot_count = 0
    for c in valid_cells:
        # Binary: b5 b4 b3 b2 b1 b0 (where bit 5=dot1, bit 4=dot2, bit 3=dot3, bit 2=dot4, bit 1=dot5, bit 0=dot6)
        # Check bits:
        # Dot 1: (c >> 5) & 1
        # Dot 2: (c >> 4) & 1
        # Dot 3: (c >> 3) & 1
        # Dot 4: (c >> 2) & 1
        # Dot 5: (c >> 1) & 1
        # Dot 6: c & 1
        d1 = (c >> 5) & 1
        d2 = (c >> 4) & 1
        d3 = (c >> 3) & 1
        d4 = (c >> 2) & 1
        d5 = (c >> 1) & 1
        d6 = c & 1
        upper_dot_count += (d1 + d2 + d4 + d5)
        lower_dot_count += (d3 + d6)

    total_dots = max(1, upper_dot_count + lower_dot_count)
    upper_dot_ratio = upper_dot_count / float(total_dots)

    # Natural English Braille has upper_dot_ratio ~ 0.70 to 0.85
    # Punctuation ratio ~ 0.02 to 0.12
    # Inverted Braille has punct_ratio > 0.35 and upper_dot_ratio < 0.50
    score = (freq_letter_ratio * 50.0) + (upper_dot_ratio * 30.0) - (punct_ratio * 70.0)

    # Heavy penalty if punctuation dominates
    if punct_ratio > 0.25:
        score -= (punct_ratio - 0.25) * 100.0

    return float(score)


def detect_orientation(
    image: np.ndarray,
    scorer_fn: Optional[Any] = None,
    use_shadow_vectors: bool = True
) -> Tuple[int, np.ndarray, Dict[str, Any]]:
    """
    Detects 0°, 90°, 180°, or 270° orientation of the Braille image.
    Uses shadow gradient vectors combined with 2-pass Braille cell distribution scoring.
    
    Returns:
        (best_rotation_degrees, corrected_image, metrics_dict)
    """
    h, w = image.shape[:2]
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if len(image.shape) == 3 else image.copy()

    # Step 1: Detect shadow gradient vectors on original orientation
    shadow_info = analyze_shadow_gradient(gray) if use_shadow_vectors else {'shadow_below': True, 'dominant_angle_deg': 90.0}

    # Step 2: Line aspect ratio test (90°/270° vs 0°/180°)
    # In horizontal text, lines are long horizontally. Horizontal projection profile variance:
    def line_profile_variance(im_gray):
        # Smooth and downsample
        small = cv2.resize(im_gray, (320, 320))
        # Otsu thresholding
        _, th = cv2.threshold(small, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
        h_proj = np.var(np.sum(th, axis=1))
        v_proj = np.var(np.sum(th, axis=0))
        return h_proj, v_proj

    scores = {}
    rot_images = {}
    rot_grays = {}
    aspect_scores = {}
    shadow_scores = {}
    shadow_belows = {}
    rotations = [0, 90, 180, 270]

    for rot in rotations:
        if rot == 0:
            rotated = image
            rot_gray = gray
        elif rot == 90:
            rotated = cv2.rotate(image, cv2.ROTATE_90_CLOCKWISE)
            rot_gray = cv2.rotate(gray, cv2.ROTATE_90_CLOCKWISE)
        elif rot == 180:
            rotated = cv2.rotate(image, cv2.ROTATE_180)
            rot_gray = cv2.rotate(gray, cv2.ROTATE_180)
        elif rot == 270:
            rotated = cv2.rotate(image, cv2.ROTATE_90_COUNTERCLOCKWISE)
            rot_gray = cv2.rotate(gray, cv2.ROTATE_90_COUNTERCLOCKWISE)

        rot_images[rot] = rotated
        rot_grays[rot] = rot_gray

        h_p, v_p = line_profile_variance(rot_gray)
        aspect_score = (h_p - v_p) / (h_p + v_p + 1e-6)
        aspect_scores[rot] = aspect_score

        # Evaluate shadow gradient at this rotation
        rot_shadow = analyze_shadow_gradient(rot_gray)
        shadow_score = 0.0
        if rot_shadow.get('pairs_count', 0) >= 8 and abs(rot_shadow.get('mean_dy', 0.0)) > 0.5:
            shadow_score = 35.0 if rot_shadow['shadow_below'] else -35.0
        shadow_scores[rot] = shadow_score
        shadow_belows[rot] = rot_shadow.get('shadow_below', True)

    # Prune candidates: only run expensive neural scorer on rotations matching text line direction
    max_aspect = max(aspect_scores.values())
    candidate_rotations = [r for r in rotations if aspect_scores[r] >= (max_aspect - 0.6)]

    for rot in rotations:
        dist_score = 0.0
        if rot in candidate_rotations and scorer_fn is not None:
            try:
                dist_score = scorer_fn(rot_images[rot])
            except Exception:
                dist_score = 0.0
        elif rot not in candidate_rotations:
            dist_score = -500.0

        total_score = (aspect_scores[rot] * 30.0) + dist_score + shadow_scores[rot]
        scores[rot] = {
            'total': total_score,
            'aspect_score': aspect_scores[rot],
            'dist_score': dist_score,
            'shadow_score': shadow_scores[rot],
            'shadow_below': shadow_belows[rot],
        }

    best_rot = max(scores.keys(), key=lambda r: scores[r]['total'])

    if best_rot == 0:
        corrected = image
    elif best_rot == 90:
        corrected = cv2.rotate(image, cv2.ROTATE_90_CLOCKWISE)
    elif best_rot == 180:
        corrected = cv2.rotate(image, cv2.ROTATE_180)
    elif best_rot == 270:
        corrected = cv2.rotate(image, cv2.ROTATE_90_COUNTERCLOCKWISE)

    return best_rot, corrected, scores
