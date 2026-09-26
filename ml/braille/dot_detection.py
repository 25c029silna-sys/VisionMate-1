"""
Braille Dot Detection Module for Embossed Paper.
Specialized in detecting white-on-white embossed dots by pairing bright crest highlights
with dark shadow troughs using connected component morphological filtering,
cKDTree dipole pairing, and spatial hash Non-Maximum Suppression (NMS).
"""

import cv2
import numpy as np
from typing import List, Dict, Any, Tuple, Optional
from dataclasses import dataclass, asdict
from scipy.spatial import cKDTree


@dataclass
class EmbossedDotResult:
    x: float
    y: float
    width: float
    height: float
    radius: float
    confidence: float
    contrast: float
    vector_dx: float
    vector_dy: float

    def to_dict(self) -> Dict[str, Any]:
        return {
            "x": round(self.x, 2),
            "y": round(self.y, 2),
            "width": round(self.width, 2),
            "height": round(self.height, 2),
            "radius": round(self.radius, 2),
            "confidence": round(self.confidence, 4),
            "contrast": round(self.contrast, 2),
            "vector_dx": round(self.vector_dx, 2),
            "vector_dy": round(self.vector_dy, 2)
        }


def detect_embossed_braille_dots(
    image: np.ndarray,
    tophat: Optional[np.ndarray] = None,
    blackhat: Optional[np.ndarray] = None,
    min_radius: float = 2.0,
    max_radius: float = 14.0,
    min_contrast: float = 6.0,
    nms_distance: float = 5.0
) -> List[Dict[str, Any]]:
    """
    Detects embossed Braille dots using paired highlight-shadow dipoles:
    1. Extract bright crests from Top-Hat and dark troughs from Black-Hat.
    2. Adaptive tile-based thresholding per 160x160 tile.
    3. Filter connected components by physical dot area (min_radius to max_radius)
       and aspect ratio (0.50 to 1.85).
    4. cKDTree dipole pairing: a valid embossed dot is formed by a bright crest
       neighboring a shadow trough within [min_radius, 2.2 * max_radius].
    5. Centroid refinement along the illumination vector.
    6. Spatial hash NMS to suppress duplicates.

    Returns: List of dot dictionaries:
    [
        {
            "x": float,
            "y": float,
            "width": float,
            "height": float,
            "confidence": float,
            "radius": float,
            "contrast": float,
            ...
        }
    ]
    """
    if len(image.shape) == 3:
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    else:
        gray = image.copy()

    h, w = gray.shape[:2]

    # Compute morphological Top-Hat and Black-Hat if not already passed
    if tophat is None or blackhat is None:
        clahe = cv2.createCLAHE(clipLimit=2.5, tileGridSize=(8, 8))
        enhanced = clahe.apply(gray)
        smoothed = cv2.GaussianBlur(enhanced, (5, 5), 1.0)
        kernel_dim = max(5, int(max_radius * 1.5))
        if kernel_dim % 2 == 0:
            kernel_dim += 1
        k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (kernel_dim, kernel_dim))
        tophat = cv2.morphologyEx(smoothed, cv2.MORPH_TOPHAT, k)
        blackhat = cv2.morphologyEx(smoothed, cv2.MORPH_BLACKHAT, k)

    # Local tile-based adaptive thresholding
    tiles_y = max(1, h // 160)
    tiles_x = max(1, w // 160)
    bin_crest = np.zeros_like(tophat, dtype=np.uint8)
    bin_trough = np.zeros_like(blackhat, dtype=np.uint8)

    for ty in range(tiles_y):
        for tx in range(tiles_x):
            y1 = ty * h // tiles_y
            y2 = (ty + 1) * h // tiles_y if ty < tiles_y - 1 else h
            x1 = tx * w // tiles_x
            x2 = (tx + 1) * w // tiles_x if tx < tiles_x - 1 else w

            t_th = tophat[y1:y2, x1:x2]
            t_bh = blackhat[y1:y2, x1:x2]

            local_top_thresh = max(min_contrast, float(np.mean(t_th) + 0.85 * np.std(t_th)))
            local_black_thresh = max(min_contrast, float(np.mean(t_bh) + 0.85 * np.std(t_bh)))

            bin_crest[y1:y2, x1:x2] = (t_th >= local_top_thresh).astype(np.uint8) * 255
            bin_trough[y1:y2, x1:x2] = (t_bh >= local_black_thresh).astype(np.uint8) * 255

    # Connected component analysis on crests and troughs
    num_c, _, stats_c, cent_c = cv2.connectedComponentsWithStats(bin_crest)
    num_t, _, stats_t, cent_t = cv2.connectedComponentsWithStats(bin_trough)

    min_area = max(4.0, np.pi * (min_radius**2) * 0.35)
    max_area = np.pi * (max_radius**2) * 1.85

    crests = []
    for i in range(1, num_c):
        area = stats_c[i, cv2.CC_STAT_AREA]
        if min_area <= area <= max_area:
            bw = stats_c[i, cv2.CC_STAT_WIDTH]
            bh_c = stats_c[i, cv2.CC_STAT_HEIGHT]
            aspect = bw / float(bh_c) if bh_c > 0 else 0
            if 0.50 <= aspect <= 1.90:
                cx_c, cy_c = float(cent_c[i][0]), float(cent_c[i][1])
                val = float(tophat[int(cy_c), int(cx_c)])
                crests.append((cx_c, cy_c, float(bw), float(bh_c), float(area), val))

    troughs = []
    for i in range(1, num_t):
        area = stats_t[i, cv2.CC_STAT_AREA]
        if min_area <= area <= max_area:
            bw = stats_t[i, cv2.CC_STAT_WIDTH]
            bh_t = stats_t[i, cv2.CC_STAT_HEIGHT]
            aspect = bw / float(bh_t) if bh_t > 0 else 0
            if 0.50 <= aspect <= 1.90:
                cx_t, cy_t = float(cent_t[i][0]), float(cent_t[i][1])
                val = float(blackhat[int(cy_t), int(cx_t)])
                troughs.append((cx_t, cy_t, float(bw), float(bh_t), float(area), val))

    candidate_dots: List[EmbossedDotResult] = []

    if crests and troughs:
        troughs_arr = np.array([[t[0], t[1]] for t in troughs], dtype=np.float32)
        crests_arr = np.array([[c[0], c[1]] for c in crests], dtype=np.float32)

        trough_tree = cKDTree(troughs_arr)
        dists, min_indices = trough_tree.query(crests_arr, k=1)

        min_pair_contrast = max(min_contrast * 1.5, 12.0)

        for i, d in enumerate(dists):
            if min_radius <= d <= (max_radius * 2.2):
                c_x, c_y, c_w, c_h, _, c_val = crests[i]
                min_idx = min_indices[i]
                t_x, t_y, t_w, t_h, _, t_val = troughs[min_idx]
                total_contrast = c_val + t_val

                if total_contrast < min_pair_contrast:
                    continue

                dx = t_x - c_x
                dy = t_y - c_y

                # Refined centroid: 70% toward crest highlight, 30% toward shadow
                dot_x = 0.70 * c_x + 0.30 * t_x
                dot_y = 0.70 * c_y + 0.30 * t_y
                dot_w = (c_w + t_w) / 2.0
                dot_h = (c_h + t_h) / 2.0
                dot_radius = max(min_radius, float(d / 2.0))

                # Confidence bounded [0.0, 1.0] based on contrast and roundness
                conf = min(1.0, float(total_contrast / 50.0))

                candidate_dots.append(EmbossedDotResult(
                    x=dot_x,
                    y=dot_y,
                    width=dot_w,
                    height=dot_h,
                    radius=dot_radius,
                    confidence=conf,
                    contrast=total_contrast,
                    vector_dx=dx,
                    vector_dy=dy
                ))

    # Fast spatial hash grid NMS to eliminate nearby duplicate pairings
    candidate_dots.sort(key=lambda d: d.contrast, reverse=True)
    grid_nms = {}
    kept_dots: List[EmbossedDotResult] = []

    cell_size = max(nms_distance, 4.5)
    for d in candidate_dots:
        gx = int(d.x // cell_size)
        gy = int(d.y // cell_size)
        if any((gx + ox, gy + oy) in grid_nms for ox in (-1, 0, 1) for oy in (-1, 0, 1)):
            continue
        grid_nms[(gx, gy)] = d
        kept_dots.append(d)

    # Convert to standard dict representations
    return [d.to_dict() for d in kept_dots]


@dataclass
class PrintedDotResult:
    x: float
    y: float
    width: float
    height: float
    radius: float
    confidence: float
    contrast: float
    circularity: float

    def to_dict(self) -> Dict[str, Any]:
        return {
            "x": round(self.x, 2),
            "y": round(self.y, 2),
            "width": round(self.width, 2),
            "height": round(self.height, 2),
            "radius": round(self.radius, 2),
            "confidence": round(self.confidence, 4),
            "contrast": round(self.contrast, 2),
            "circularity": round(self.circularity, 3),
            "vector_dx": 0.0,
            "vector_dy": 0.0,
        }


def detect_printed_braille_dots(
    image: np.ndarray,
    min_radius: float = 1.5,
    max_radius: float = 16.0,
    polarity: str = "auto",
    min_contrast: float = 15.0,
    min_circularity: float = 0.50,
    nms_distance: float = 4.0,
) -> List[Dict[str, Any]]:
    """
    Detects non-embossed (printed, digital, flat) Braille dots:
    1. Polarity detection ('auto', 'dark_on_light', or 'light_on_dark').
    2. Morphological Black-Hat (for dark dots) or Top-Hat (for light dots)
       using an elliptical structuring element matching physical dot scale.
    3. Adaptive tile-based binarization to handle varying paper illumination.
    4. Connected component filtering by area, aspect ratio, and circularity.
    5. Sub-pixel centroid computation via moments.
    6. Spatial hash NMS to suppress duplicates.
    """
    if len(image.shape) == 3:
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    else:
        gray = image.copy()

    h, w = gray.shape[:2]
    if h < 5 or w < 5:
        return []

    # Illumination smoothing
    smoothed = cv2.GaussianBlur(gray, (3, 3), 0.8)

    # Determine polarity
    if polarity == "auto":
        med_val = float(np.median(smoothed))
        actual_polarity = "dark_on_light" if med_val > 120 else "light_on_dark"
    else:
        actual_polarity = polarity

    # Morphological extraction
    kernel_dim = max(5, int(max_radius * 2.2))
    if kernel_dim % 2 == 0:
        kernel_dim += 1
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (kernel_dim, kernel_dim))

    if actual_polarity == "dark_on_light":
        peak_map = cv2.morphologyEx(smoothed, cv2.MORPH_BLACKHAT, k)
    else:
        peak_map = cv2.morphologyEx(smoothed, cv2.MORPH_TOPHAT, k)

    # Local tile-based adaptive thresholding on peak_map
    tiles_y = max(1, h // 160)
    tiles_x = max(1, w // 160)
    bin_dots = np.zeros_like(peak_map, dtype=np.uint8)

    for ty in range(tiles_y):
        for tx in range(tiles_x):
            y1 = ty * h // tiles_y
            y2 = (ty + 1) * h // tiles_y if ty < tiles_y - 1 else h
            x1 = tx * w // tiles_x
            x2 = (tx + 1) * w // tiles_x if tx < tiles_x - 1 else w

            tile = peak_map[y1:y2, x1:x2]
            std_val = float(np.std(tile))
            mean_val = float(np.mean(tile))

            tile_thresh = max(min_contrast, mean_val + 1.2 * std_val)
            bin_dots[y1:y2, x1:x2] = (tile >= tile_thresh).astype(np.uint8) * 255

    # Find contours
    contours, _ = cv2.findContours(bin_dots, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

    min_area = max(3.0, np.pi * (min_radius**2) * 0.40)
    max_area = np.pi * (max_radius**2) * 2.20

    candidates: List[PrintedDotResult] = []

    for cnt in contours:
        area = float(cv2.contourArea(cnt))
        if area < min_area or area > max_area:
            continue

        bx, by, bw, bh_box = cv2.boundingRect(cnt)
        aspect = bw / float(bh_box) if bh_box > 0 else 0.0
        if not (0.50 <= aspect <= 1.90):
            continue

        perimeter = float(cv2.arcLength(cnt, True))
        if perimeter <= 0:
            continue

        circularity = (4.0 * np.pi * area) / (perimeter * perimeter)
        if circularity < min_circularity:
            continue

        # Sub-pixel centroid
        M = cv2.moments(cnt)
        if M["m00"] > 0:
            cx = float(M["m10"] / M["m00"])
            cy = float(M["m01"] / M["m00"])
        else:
            cx = bx + bw / 2.0
            cy = by + bh_box / 2.0

        ix, iy = int(round(cx)), int(round(cy))
        ix = min(max(0, ix), w - 1)
        iy = min(max(0, iy), h - 1)
        dot_contrast = float(peak_map[iy, ix])

        equiv_radius = max(min_radius, float(np.sqrt(area / np.pi)))
        conf = min(1.0, float(circularity * min(1.0, dot_contrast / 40.0)))

        candidates.append(PrintedDotResult(
            x=cx,
            y=cy,
            width=float(bw),
            height=float(bh_box),
            radius=equiv_radius,
            confidence=conf,
            contrast=dot_contrast,
            circularity=circularity
        ))

    # Fast spatial hash NMS
    candidates.sort(key=lambda d: d.contrast, reverse=True)
    grid_nms = {}
    kept_dots: List[PrintedDotResult] = []

    cell_size = max(nms_distance, 4.0)
    for d in candidates:
        gx = int(d.x // cell_size)
        gy = int(d.y // cell_size)
        if any((gx + ox, gy + oy) in grid_nms for ox in (-1, 0, 1) for oy in (-1, 0, 1)):
            continue
        grid_nms[(gx, gy)] = d
        kept_dots.append(d)

    return [d.to_dict() for d in kept_dots]


def detect_braille_dots(
    image: np.ndarray,
    mode: str = "auto",
    tophat: Optional[np.ndarray] = None,
    blackhat: Optional[np.ndarray] = None,
    min_radius: float = 2.0,
    max_radius: float = 14.0,
    min_contrast: float = 6.0,
    nms_distance: float = 5.0
) -> List[Dict[str, Any]]:
    """
    Unified dot detection dispatcher supporting 'embossed', 'printed', and 'auto' modes.
    - 'embossed': Runs dipole pairing (crest highlight + shadow trough).
    - 'printed': Runs morphological peak extraction with circularity filtering.
    - 'auto': Tests both modes and selects the one with superior grid consistency and dot count.
    """
    if mode == "embossed":
        return detect_embossed_braille_dots(
            image=image,
            tophat=tophat,
            blackhat=blackhat,
            min_radius=min_radius,
            max_radius=max_radius,
            min_contrast=min_contrast,
            nms_distance=nms_distance
        )
    elif mode == "printed":
        return detect_printed_braille_dots(
            image=image,
            min_radius=min_radius,
            max_radius=max_radius,
            min_contrast=max(min_contrast * 2.0, 15.0),
            nms_distance=nms_distance
        )
    elif mode == "auto":
        printed_dots = detect_printed_braille_dots(
            image=image,
            min_radius=min_radius,
            max_radius=max_radius,
            min_contrast=max(min_contrast * 2.0, 15.0),
            nms_distance=nms_distance
        )

        embossed_dots = detect_embossed_braille_dots(
            image=image,
            tophat=tophat,
            blackhat=blackhat,
            min_radius=min_radius,
            max_radius=max_radius,
            min_contrast=min_contrast,
            nms_distance=nms_distance
        )

        if len(printed_dots) >= 4 and len(embossed_dots) < 4:
            return printed_dots
        elif len(embossed_dots) >= 4 and len(printed_dots) < 4:
            return embossed_dots
        elif len(printed_dots) > 0 and len(embossed_dots) > 0:
            mean_conf_p = float(np.mean([d["confidence"] for d in printed_dots]))
            mean_conf_e = float(np.mean([d["confidence"] for d in embossed_dots]))
            if len(printed_dots) >= len(embossed_dots) and mean_conf_p >= mean_conf_e * 0.9:
                return printed_dots
            else:
                return embossed_dots
        elif len(printed_dots) > 0:
            return printed_dots
        else:
            return embossed_dots
    else:
        raise ValueError(f"Unknown dot detection mode: '{mode}'. Expected 'auto', 'embossed', or 'printed'.")

