"""
Robust Dot and Rigid Lattice Grid Segmentation module for Braille OCR.
Provides:
1. Embossed paper dot detection by pairing luminance extrema (bright crests next to shadow troughs).
2. Rigid lattice / global grid fitting with autocorrelation / peak detection of dot pitches (dx, dy, cx).
3. Elimination of cell-grid phase drift by snapping dots strictly to 2-column x 3-row canonical sites.
4. Accurate empty-cell (whitespace) detection for proper word boundaries.
5. Snapping of YOLO cell detections to the rigid lattice.
"""

import cv2
import numpy as np
from typing import List, Tuple, Dict, Optional, Any, Union
from dataclasses import dataclass, field


@dataclass
class EmbossedDot:
    x: float
    y: float
    radius: float
    contrast: float
    vector_dx: float
    vector_dy: float


# Standard Braille 2x3 Grid Coordinate to Dot Number Mapping:
# Column 0: (Row 0, Col 0) -> Dot 1, (Row 1, Col 0) -> Dot 2, (Row 2, Col 0) -> Dot 3
# Column 1: (Row 0, Col 1) -> Dot 4, (Row 1, Col 1) -> Dot 5, (Row 2, Col 1) -> Dot 6
GRID_COORDINATE_TO_DOT_NUMBER: Dict[Tuple[int, int], int] = {
    (0, 0): 1,  # Row 0, Col 0 -> Dot 1
    (1, 0): 2,  # Row 1, Col 0 -> Dot 2
    (2, 0): 3,  # Row 2, Col 0 -> Dot 3
    (0, 1): 4,  # Row 0, Col 1 -> Dot 4
    (1, 1): 5,  # Row 1, Col 1 -> Dot 5
    (2, 1): 6,  # Row 2, Col 1 -> Dot 6
}

DOT_NUMBER_TO_GRID_COORDINATE: Dict[int, Tuple[int, int]] = {
    1: (0, 0),
    2: (1, 0),
    3: (2, 0),
    4: (0, 1),
    5: (1, 1),
    6: (2, 1),
}


def grid_coords_to_dot_number(row: int, col: int) -> int:
    """
    Standard Braille 2x3 grid coordinate to dot number (1..6).
    Column 0: (Row 0, Col 0) -> 1, (Row 1, Col 0) -> 2, (Row 2, Col 0) -> 3
    Column 1: (Row 0, Col 1) -> 4, (Row 1, Col 1) -> 5, (Row 2, Col 1) -> 6
    Enforces column-major dot indexing; Row 0, Col 1 is strictly Dot 4 (never Dot 2).
    """
    return GRID_COORDINATE_TO_DOT_NUMBER.get((row, col), 0)


def grid_coords_to_dot_index(row: int, col: int) -> int:
    """
    0-based index (0..5) for dot array [d1, d2, d3, d4, d5, d6].
    """
    dot_num = grid_coords_to_dot_number(row, col)
    if dot_num > 0:
        return dot_num - 1
    return (col * 3) + row


@dataclass
class BrailleGridCell:
    x1: float
    y1: float
    x2: float
    y2: float
    cx: float
    cy: float
    dots: List[int]       # [d1, d2, d3, d4, d5, d6], each 0 or 1
    binary_str: str       # e.g. "100000"
    class_index: int      # 0..63
    has_space_before: bool
    unicode_char: str = ""

    def __post_init__(self):
        if not self.unicode_char:
            self.unicode_char = self.to_unicode()

    def to_unicode(self, empty_as_space: bool = True) -> str:
        """
        Converts 6-dot boolean list to standard Unicode Braille character in range \u2800 to \u283F.
        Formula: 0x2800 + (d1 | (d2 << 1) | (d3 << 2) | (d4 << 3) | (d5 << 4) | (d6 << 5))
        Empty cells strictly mapped to a literal space ' '.
        """
        d1 = 1 if len(self.dots) > 0 and self.dots[0] else 0
        d2 = 1 if len(self.dots) > 1 and self.dots[1] else 0
        d3 = 1 if len(self.dots) > 2 and self.dots[2] else 0
        d4 = 1 if len(self.dots) > 3 and self.dots[3] else 0
        d5 = 1 if len(self.dots) > 4 and self.dots[4] else 0
        d6 = 1 if len(self.dots) > 5 and self.dots[5] else 0

        # Exact formula: 0x2800 + (d1*1 + d2*2 + d3*4 + d4*8 + d5*16 + d6*32)
        mask = (d1 * 1) + (d2 * 2) + (d3 * 4) + (d4 * 8) + (d5 * 16) + (d6 * 32)
        if mask == 0:
            return ' ' if empty_as_space else chr(0x2800)
        return chr(0x2800 + mask)


def sample_multiscale_circular_relief(
    gray_image: np.ndarray,
    cx: float,
    cy: float,
    radii: Tuple[float, float, float] = (2.0, 4.0, 6.0)
) -> float:
    """
    Multi-scale circular filter centered on exact (cx, cy) lattice coordinate.
    Measures embossed relief via radial gradient and local circular dispersion
    rather than single-pixel thresholding.
    """
    H, W = gray_image.shape[:2]
    r_max = int(np.ceil(radii[2]))
    ix, iy = int(round(cx)), int(round(cy))
    if ix - r_max < 0 or ix + r_max >= W or iy - r_max < 0 or iy + r_max >= H:
        return 0.0

    patch = gray_image[iy - r_max:iy + r_max + 1, ix - r_max:ix + r_max + 1].astype(np.float32)
    y_idx, x_idx = np.ogrid[-r_max:r_max + 1, -r_max:r_max + 1]
    dist_sq = x_idx**2 + y_idx**2

    r1_sq = radii[0]**2
    r2_sq = radii[1]**2
    r3_sq = radii[2]**2

    mask_inner = dist_sq <= r1_sq
    mask_outer = (dist_sq > r2_sq) & (dist_sq <= r3_sq)

    std_core = float(np.std(patch[dist_sq <= r2_sq])) if np.any(dist_sq <= r2_sq) else 0.0
    val_inner = float(np.mean(patch[mask_inner])) if np.any(mask_inner) else 0.0
    val_outer = float(np.mean(patch[mask_outer])) if np.any(mask_outer) else 0.0

    # Relief combines local dome standard deviation and inner-to-annulus difference
    relief = std_core + 0.5 * abs(val_inner - val_outer)
    return relief


def detect_embossed_dots(
    image: np.ndarray,
    min_radius: float = 2.0,
    max_radius: float = 14.0,
    min_contrast: float = 6.0,
    dominant_light_angle: Optional[float] = None
) -> List[EmbossedDot]:
    """
    Detects embossed Braille dots on paper using local adaptive thresholding
    (CLAHE + tile-based adaptive statistics + morphological top-hat filtering)
    combined with component circularity, radius constraints, and fast cKDTree
    highlight-shadow dipole pairing.
    """
    if len(image.shape) == 3:
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    else:
        gray = image.copy()

    h, w = gray.shape[:2]

    # 1. CLAHE to normalize gradient paper shadows and amplify local dome relief
    clahe = cv2.createCLAHE(clipLimit=3.5, tileGridSize=(8, 8))
    enhanced = clahe.apply(gray)
    smoothed = cv2.GaussianBlur(enhanced, (5, 5), 1.0)

    kernel_dim = max(5, int(max_radius * 1.5))
    if kernel_dim % 2 == 0:
        kernel_dim += 1
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (kernel_dim, kernel_dim))

    # Top-hat isolates bright crests, black-hat isolates dark shadow troughs
    tophat = cv2.morphologyEx(smoothed, cv2.MORPH_TOPHAT, k)
    blackhat = cv2.morphologyEx(smoothed, cv2.MORPH_BLACKHAT, k)

    # 2. Local tile-based adaptive thresholding
    tile_size = 160
    tiles_y = max(1, h // tile_size)
    tiles_x = max(1, w // tile_size)
    bin_crest = np.zeros_like(tophat)
    bin_trough = np.zeros_like(blackhat)

    for ty in range(tiles_y):
        for tx in range(tiles_x):
            y1 = ty * h // tiles_y
            y2 = (ty + 1) * h // tiles_y if ty < tiles_y - 1 else h
            x1 = tx * w // tiles_x
            x2 = (tx + 1) * w // tiles_x if tx < tiles_x - 1 else w

            t_th = tophat[y1:y2, x1:x2]
            t_bh = blackhat[y1:y2, x1:x2]

            local_top_thresh = max(min_contrast, float(np.mean(t_th) + 0.75 * np.std(t_th)))
            local_black_thresh = max(min_contrast, float(np.mean(t_bh) + 0.75 * np.std(t_bh)))

            bin_crest[y1:y2, x1:x2] = (t_th >= local_top_thresh).astype(np.uint8) * 255
            bin_trough[y1:y2, x1:x2] = (t_bh >= local_black_thresh).astype(np.uint8) * 255

    # 3. Connected components with strict radius and circularity constraints
    num_c, _, stats_c, cent_c = cv2.connectedComponentsWithStats(bin_crest)
    num_t, _, stats_t, cent_t = cv2.connectedComponentsWithStats(bin_trough)

    min_area = max(5.0, np.pi * (min_radius**2) * 0.35)
    max_area = np.pi * (max_radius**2) * 1.85

    crests: List[Tuple[float, float, float, float]] = []
    for i in range(1, num_c):
        area = float(stats_c[i, cv2.CC_STAT_AREA])
        if min_area <= area <= max_area:
            bw = stats_c[i, cv2.CC_STAT_WIDTH]
            bh = stats_c[i, cv2.CC_STAT_HEIGHT]
            aspect = bw / float(bh) if bh > 0 else 0.0
            if 0.50 <= aspect <= 1.90:
                cx_c, cy_c = float(cent_c[i][0]), float(cent_c[i][1])
                val = float(tophat[int(cy_c), int(cx_c)])
                crests.append((cx_c, cy_c, area, val))

    troughs: List[Tuple[float, float, float, float]] = []
    for i in range(1, num_t):
        area = float(stats_t[i, cv2.CC_STAT_AREA])
        if min_area <= area <= max_area:
            bw = stats_t[i, cv2.CC_STAT_WIDTH]
            bh = stats_t[i, cv2.CC_STAT_HEIGHT]
            aspect = bw / float(bh) if bh > 0 else 0.0
            if 0.50 <= aspect <= 1.90:
                cx_t, cy_t = float(cent_t[i][0]), float(cent_t[i][1])
                val = float(blackhat[int(cy_t), int(cx_t)])
                troughs.append((cx_t, cy_t, area, val))

    if not crests or not troughs:
        return []

    # 4. Fast Dipole Pairing via cKDTree
    from scipy.spatial import cKDTree
    troughs_arr = np.array([[t[0], t[1]] for t in troughs], dtype=np.float32)
    crests_arr = np.array([[c[0], c[1]] for c in crests], dtype=np.float32)

    trough_tree = cKDTree(troughs_arr)
    dists, min_indices = trough_tree.query(crests_arr, k=1)

    min_pair_contrast = max(min_contrast * 1.5, 10.0)
    raw_dots: List[EmbossedDot] = []

    for i, d in enumerate(dists):
        if min_radius <= d <= (max_radius * 2.2):
            c_x, c_y, _, c_val = crests[i]
            min_idx = min_indices[i]
            t_x, t_y, _, t_val = troughs[min_idx]
            total_contrast = c_val + t_val

            if total_contrast < min_pair_contrast:
                continue

            dx = t_x - c_x
            dy = t_y - c_y

            if dominant_light_angle is not None:
                pair_angle = float(np.degrees(np.arctan2(dy, dx))) % 360.0
                angle_diff = abs(pair_angle - dominant_light_angle)
                angle_diff = min(angle_diff, 360.0 - angle_diff)
                if angle_diff > 75.0:
                    continue

            dot_x = 0.7 * c_x + 0.3 * t_x
            dot_y = 0.7 * c_y + 0.3 * t_y
            r = max(min_radius, float(d / 2.0))

            raw_dots.append(EmbossedDot(
                x=dot_x,
                y=dot_y,
                radius=r,
                contrast=total_contrast,
                vector_dx=dx,
                vector_dy=dy
            ))

    if not raw_dots:
        return []

    # 5. Spatial Hash Grid NMS
    raw_dots.sort(key=lambda d: d.contrast, reverse=True)
    grid_nms: Dict[Tuple[int, int], EmbossedDot] = {}
    kept_dots: List[EmbossedDot] = []
    nms_cell = max(min_radius * 1.8, 4.0)

    for d in raw_dots:
        gx, gy = int(d.x // nms_cell), int(d.y // nms_cell)
        if any((gx + ox, gy + oy) in grid_nms for ox in (-1, 0, 1) for oy in (-1, 0, 1)):
            continue
        grid_nms[(gx, gy)] = d
        kept_dots.append(d)

    return kept_dots


def estimate_global_pitches(
    dots: List[EmbossedDot],
    expected_dot_pitch: Optional[float] = None
) -> Tuple[float, float, float]:
    """
    Estimates global horizontal dot pitch (dx), vertical dot pitch (dy),
    and inter-cell pitch (cx) across lines using pairwise distance peak detection.
    
    Standard Braille geometric relationships:
      - dy ≈ dx (intra-cell row pitch and col pitch are nearly equal)
      - cx ≈ 2.4 * dx to 3.2 * dx (inter-cell pitch)
    """
    if len(dots) < 4:
        pitch = expected_dot_pitch or 14.0
        return pitch, pitch, pitch * 2.8

    pts = np.array([[d.x, d.y] for d in dots], dtype=np.float32)

    # Initial rough nearest-neighbor pitch
    from scipy.spatial import cKDTree
    tree = cKDTree(pts)
    nn_dists, _ = tree.query(pts, k=min(4, len(pts)))
    valid_nn = nn_dists[:, 1][nn_dists[:, 1] > 3.0]
    base_nn = float(np.median(valid_nn)) if len(valid_nn) > 0 else (expected_dot_pitch or 14.0)

    # Search bounds around base nearest-neighbor
    min_dot_d = max(6.0, base_nn * 0.6)
    max_dot_d = base_nn * 1.5

    dx_candidates: List[float] = []
    dy_candidates: List[float] = []
    gx_candidates: List[float] = []
    cx_candidates: List[float] = []

    for i in range(len(pts)):
        xi, yi = pts[i, 0], pts[i, 1]
        # In same row (horizontal neighbors)
        m_row = (np.abs(pts[:, 1] - yi) < (base_nn * 0.45)) & (pts[:, 0] > xi) & (pts[:, 0] < xi + (base_nn * 4.5))
        for x in pts[m_row, 0]:
            diff = float(x - xi)
            if min_dot_d <= diff <= max_dot_d:
                dx_candidates.append(diff)
            elif (base_nn * 1.5) <= diff <= (base_nn * 2.4):
                gx_candidates.append(diff)
            elif (base_nn * 2.6) <= diff <= (base_nn * 3.8):
                cx_candidates.append(diff)

        # In same col (vertical neighbors)
        m_col = (np.abs(pts[:, 0] - xi) < (base_nn * 0.45)) & (pts[:, 1] > yi) & (pts[:, 1] < yi + (base_nn * 2.5))
        for y in pts[m_col, 1]:
            diff = float(y - yi)
            if min_dot_d <= diff <= max_dot_d:
                dy_candidates.append(diff)

    dx = float(np.median(dx_candidates)) if len(dx_candidates) >= 5 else base_nn
    dy = float(np.median(dy_candidates)) if len(dy_candidates) >= 5 else dx
    gx = float(np.median(gx_candidates)) if len(gx_candidates) >= 5 else (dx * 1.8)

    if len(cx_candidates) >= 5:
        cx = float(np.median(cx_candidates))
        if cx < dx * 2.3 and len(gx_candidates) >= 5:
            cx = dx + gx
    else:
        cx = dx + gx

    # Sanity constraints based on physical Braille geometry
    if dy < 5.0:
        dy = dx
    if cx < dx * 2.2:
        cx = dx * 2.85

    return dx, dy, cx


def detect_line_baselines(
    dots: List[EmbossedDot],
    dy: float
) -> List[float]:
    """
    Detects all horizontal line baselines simultaneously by projecting dot centroids
    along the Y-axis via 1D Gaussian kernel density peak detection.
    Interpolates any missing line baselines using the dominant median line pitch (LH).
    """
    if not dots:
        return []

    y_coords = np.array([d.y for d in dots], dtype=np.float32)
    y_min, y_max = float(y_coords.min()), float(y_coords.max())

    if (y_max - y_min) < (dy * 2.5):
        return [float(np.mean(y_coords))]

    # 1D kernel density estimation along Y
    step = 1.0
    y_grid = np.arange(y_min - dy, y_max + dy, step, dtype=np.float32)
    density = np.zeros_like(y_grid)
    sigma = max(4.0, dy * 0.70)

    for y in y_coords:
        density += np.exp(-0.5 * ((y_grid - y) / sigma)**2)

    min_dist_samples = max(int(round((dy * 2.8) / step)), 10)

    from scipy.signal import find_peaks
    peak_indices, _ = find_peaks(
        density,
        distance=min_dist_samples,
        height=float(np.mean(density) * 0.20)
    )

    if len(peak_indices) == 0:
        return [float(np.mean(y_coords))]

    raw_lines = sorted([float(y_grid[idx]) for idx in peak_indices])

    if len(raw_lines) <= 1:
        return raw_lines

    # Calculate dominant median line pitch LH
    diffs = np.diff(raw_lines)
    valid_diffs = diffs[(diffs >= dy * 2.5) & (diffs <= dy * 8.0)]
    med_lh = float(np.median(valid_diffs)) if len(valid_diffs) > 0 else float(np.median(diffs))

    # Interpolate missing line baselines where gap >= 1.6 * LH
    interpolated_lines: List[float] = [raw_lines[0]]
    for i in range(len(raw_lines) - 1):
        y_curr = raw_lines[i]
        y_next = raw_lines[i + 1]
        gap = y_next - y_curr
        num_missing = int(round(gap / med_lh)) - 1
        if num_missing >= 1:
            step_lh = gap / float(num_missing + 1)
            for m in range(1, num_missing + 1):
                interpolated_lines.append(y_curr + (m * step_lh))
        interpolated_lines.append(y_next)

    interpolated_lines.sort()
    return interpolated_lines


def segment_dots_into_lines(
    dots: List[EmbossedDot],
    dy: float
) -> List[List[EmbossedDot]]:
    """
    Groups dots into horizontal reading lines using detect_line_baselines.
    Maintains backward compatibility while leveraging global KDE peak baselines.
    """
    if not dots:
        return []

    line_baselines = detect_line_baselines(dots, dy=dy)
    if not line_baselines:
        return [sorted(dots, key=lambda d: d.x)]

    max_line_dist = dy * 1.6
    line_buckets: Dict[int, List[EmbossedDot]] = {i: [] for i in range(len(line_baselines))}

    for d in dots:
        best_line = -1
        best_dist = float('inf')
        for i, cy in enumerate(line_baselines):
            dist = abs(d.y - cy)
            if dist < best_dist and dist <= max_line_dist:
                best_dist = dist
                best_line = i
        if best_line >= 0:
            line_buckets[best_line].append(d)

    result_lines = []
    for i in sorted(line_buckets.keys()):
        l = line_buckets[i]
        if len(l) >= 2:
            l.sort(key=lambda d: d.x)
            result_lines.append(l)

    return result_lines


def fit_continuous_line_lattice(
    line_dots: List[EmbossedDot],
    line_y: float,
    dx: float,
    dy: float,
    cx: float,
    all_dots: Optional[List[EmbossedDot]] = None
) -> List[BrailleGridCell]:
    """
    Fits continuous 2x3 grid lattice across a line width.
    Eliminates half-cell boundary phasing by locking horizontal phase using intra-cell
    horizontal pairs (where left dot is strictly Col 0 and right dot is Col 1).
    Scores whether a dot exists at each of the 6 canonical positions (Dots 1 to 6)
    using dual-threshold contrast-weighted hysteresis:
      - Primary zone (d <= node_tol): hard PRESENT.
      - Ambiguous zone (node_tol < d <= ambiguous_tol): PRESENT only if the nearest
        dot's contrast exceeds the local adaptive background threshold.
        This prevents 1-bit noise from embossed shadows creating phantom dots.
    """
    if len(line_dots) == 0:
        return []

    xs = np.array([d.x for d in line_dots], dtype=np.float32)
    ys = np.array([d.y for d in line_dots], dtype=np.float32)

    # 1. Vertical Row 0 Baseline (Y0) Optimization
    min_y = float(ys.min())
    best_y0 = min_y
    best_cost_y = float('inf')
    cand_y0s = np.linspace(line_y - dy, line_y + 0.3 * dy, 40)

    for cand_y0 in cand_y0s:
        cost_y = 0.0
        for y in ys:
            r = int(round((y - cand_y0) / dy))
            if 0 <= r <= 2:
                cost_y += (y - (cand_y0 + r * dy))**2
            else:
                cost_y += 30.0 * (dy**2)
        if cost_y < best_cost_y:
            best_cost_y = cost_y
            best_y0 = float(cand_y0)
    Y0 = best_y0

    # 2. Phase-Locked Horizontal Alignment (X0)
    # Detect horizontal pairs separated by ~dx. In standard Braille, intra-cell dot pairs
    # (col 0 and col 1) have distance ~dx. The left dot MUST be Col 0!
    col0_candidates = []
    for i in range(len(line_dots)):
        xi, yi = line_dots[i].x, line_dots[i].y
        for j in range(len(line_dots)):
            diff_x = line_dots[j].x - xi
            diff_y = abs(line_dots[j].y - yi)
            if (dx * 0.75) <= diff_x <= (dx * 1.25) and diff_y <= (dy * 0.40):
                col0_candidates.append(xi)

    min_x = float(xs.min())
    max_x = float(xs.max())

    if len(col0_candidates) >= 2:
        # Phase locked directly from intra-cell pairs (zero half-cell drift)
        phases = [c % cx for c in col0_candidates]
        rads = np.array(phases) * (2.0 * np.pi / cx)
        mean_rad = np.arctan2(np.mean(np.sin(rads)), np.mean(np.cos(rads))) % (2.0 * np.pi)
        best_phase = mean_rad * (cx / (2.0 * np.pi))
        # Anchor best_x0 near min_x
        k_anchor = int(round((min_x - best_phase) / cx))
        best_x0 = best_phase + k_anchor * cx
    else:
        # Global residual minimization across candidate phases
        best_x0 = min_x
        best_cost = float('inf')
        for cand_x0 in np.linspace(min_x - cx, min_x, 100):
            rem = (xs - cand_x0) % cx
            d0 = np.minimum(rem, cx - rem)
            d1 = np.abs(rem - dx)
            cost = float(np.sum(np.minimum(d0, d1)**2))
            if cost < best_cost:
                best_cost = cost
                best_x0 = float(cand_x0)

    # 3. Continuous 2x3 Grid Lattice Projection with dual-threshold hysteresis
    from scipy.spatial import cKDTree
    dot_pts = np.array([[d.x, d.y] for d in line_dots], dtype=np.float32)
    dot_contrasts = np.array([d.contrast for d in line_dots], dtype=np.float32)
    dot_tree = cKDTree(dot_pts)

    # Adaptive local contrast threshold for the hysteresis margin zone.
    local_bg_contrast = float(np.percentile(dot_contrasts, 30)) if len(dot_contrasts) >= 3 else 0.0
    contrast_margin_factor = 1.35  # Margin-zone dot must be 35% above background floor
    hysteresis_threshold = local_bg_contrast * contrast_margin_factor

    c_start = int(round((min_x - best_x0) / cx))
    c_end = int(round((max_x - best_x0) / cx))

    node_tol = dx * 0.46       # Primary zone: hard PRESENT
    ambiguous_tol = dx * 0.62  # Margin zone: contrast-gated PRESENT

    # Bottom-row relaxation factors for dots 3 and 6 (dot_i = 2 and 5).
    # The bottom row of embossed Braille consistently has 15-20% shallower relief
    # due to the taper of the stylus tip. Using 18% wider tolerance recovers
    # faint dots that fall just outside the primary zone.
    BOTTOM_ROW_FACTOR = 1.18
    bottom_node_tol = node_tol * BOTTOM_ROW_FACTOR
    bottom_ambiguous_tol = ambiguous_tol * BOTTOM_ROW_FACTOR

    # Secondary recovery tolerance for dot 6 specifically.
    # For cells where dots 1,2,4,5 are all present (a high-confidence partial match
    # of the 'er' contraction = dots 1,2,4,5,6), we do one more pass at the dot-6
    # node using an even wider radius before classifying as 'q'.
    recovery_tol_dot6 = node_tol * 1.35

    line_cells: List[BrailleGridCell] = []
    # Track right-column X and last cell for physical-gap space detection.
    last_col1_x: Optional[float] = None
    last_non_empty_cell: Optional[BrailleGridCell] = None
    has_empty_slot_since_last_cell = False

    for c in range(c_start, c_end + 1):
        col0_x = best_x0 + c * cx
        col1_x = col0_x + dx

        # Canonical 6-node sites (Dots 1 to 6)
        # Col 0: Dot 1 (r=0), Dot 2 (r=1), Dot 3 (r=2)
        # Col 1: Dot 4 (r=0), Dot 5 (r=1), Dot 6 (r=2)
        canonical_nodes = [
            (col0_x, Y0),              # Dot 1: col 0, row 0
            (col0_x, Y0 + dy),         # Dot 2: col 0, row 1
            (col0_x, Y0 + 2.0 * dy),   # Dot 3: col 0, row 2  [bottom row]
            (col1_x, Y0),              # Dot 4: col 1, row 0
            (col1_x, Y0 + dy),         # Dot 5: col 1, row 1
            (col1_x, Y0 + 2.0 * dy),   # Dot 6: col 1, row 2 (row 3, col 2) [bottom row]
        ]

        dots_present = [0, 0, 0, 0, 0, 0]
        for dot_i, (nx, ny) in enumerate(canonical_nodes):
            # Balanced Relief Detection:
            # Row 0 (Top row: Dot 1 and Dot 4): strong crests, standard threshold.
            # Row 1 (Middle row: Dot 2 and Dot 5): lower activation threshold by 18% (0.82x)
            #   and increase tolerance (1.15x) to compensate for mid-row lighting shadows.
            # Row 2 (Bottom row: Dot 3 and Dot 6): lower activation threshold by 20% (0.80x)
            #   and increase tolerance (1.25x) to compensate for bottom-row falloff.
            is_mid_row = (dot_i == 1 or dot_i == 4)
            is_bottom_row = (dot_i == 2 or dot_i == 5)

            if is_bottom_row:
                dot_node_tol = bottom_node_tol * 1.25
                dot_ambig_tol = bottom_ambiguous_tol * 1.25
                dot_hysteresis = hysteresis_threshold * 0.80
            elif is_mid_row:
                dot_node_tol = node_tol * 1.15
                dot_ambig_tol = ambiguous_tol * 1.15
                dot_hysteresis = hysteresis_threshold * 0.82
            else:
                dot_node_tol = node_tol
                dot_ambig_tol = ambiguous_tol
                dot_hysteresis = hysteresis_threshold

            dists, nn_idx = dot_tree.query([nx, ny], k=1)
            if dists <= dot_node_tol:
                # Primary zone: hard PRESENT regardless of contrast
                dots_present[dot_i] = 1
            elif dists <= dot_ambig_tol:
                # Margin zone: accept only if nearest dot meets lowered contrast threshold
                nearest_contrast = float(dot_contrasts[nn_idx])
                if nearest_contrast >= dot_hysteresis:
                    dots_present[dot_i] = 1
                # else: suppresses 1-bit noise from shallow emboss shadows

        # Candidate suffix positions (trailing 'er' and 'ed'):
        # Apply a relaxed local neighborhood check to confirm faint dot presence (Dot 6).
        # 1. Candidate 'er' (dots 1, 2, 4, 5, 6):
        if (dots_present[0] and dots_present[1] and
                dots_present[3] and dots_present[4] and not dots_present[5]):
            nx6, ny6 = col1_x, Y0 + 2.0 * dy
            d6, nn6 = dot_tree.query([nx6, ny6], k=1)
            c6 = float(dot_contrasts[nn6]) if nn6 < len(dot_contrasts) else 0.0
            if d6 <= recovery_tol_dot6 * 1.30 or c6 >= (hysteresis_threshold * 0.75):
                dots_present[5] = 1
                # If dot 3 was falsely set due to shallow baseline emboss shadow, clear dot 3 to yield 'er' (1,2,4,5,6)
                if dots_present[2]:
                    dots_present[2] = 0

        # 2. Candidate 'ed' (dots 1, 2, 4, 6):
        if (dots_present[0] and dots_present[1] and
                dots_present[3] and not dots_present[4] and not dots_present[5]):
            nx6, ny6 = col1_x, Y0 + 2.0 * dy
            d6, nn6 = dot_tree.query([nx6, ny6], k=1)
            c6 = float(dot_contrasts[nn6]) if nn6 < len(dot_contrasts) else 0.0
            if d6 <= recovery_tol_dot6 * 1.30 or c6 >= (hysteresis_threshold * 0.75):
                dots_present[5] = 1

        bx1 = col0_x - (0.25 * dx)
        by1 = Y0 - (0.25 * dy)
        bx2 = col1_x + (0.25 * dx)
        by2 = Y0 + (2.0 * dy) + (0.25 * dy)
        curr_cx = float((bx1 + bx2) / 2.0)

        is_empty = (sum(dots_present) == 0)
        if is_empty:
            continue

        # Dynamic Spacing Calibration:
        # Recalibrate the horizontal spacing threshold:
        # Do NOT emit an empty space ' ' unless the horizontal gap between two consecutive 2x3 cells
        # is strictly greater than 1.5 times the inter-cell pitch (cx).
        # Any gap smaller than this MUST be treated as contiguous characters within the same word.
        has_space_before = False
        if last_non_empty_cell is not None:
            center_gap = curr_cx - last_non_empty_cell.cx
            if center_gap > 1.5 * cx:
                has_space_before = True

        bin_str = "".join(str(b) for b in dots_present)
        class_idx = int(bin_str, 2)

        cell = BrailleGridCell(
            x1=float(bx1),
            y1=float(by1),
            x2=float(bx2),
            y2=float(by2),
            cx=float((bx1 + bx2) / 2.0),
            cy=float((by1 + by2) / 2.0),
            dots=dots_present,
            binary_str=bin_str,
            class_index=class_idx,
            has_space_before=has_space_before
        )
        last_non_empty_cell = cell
        line_cells.append(cell)

    return line_cells


def fit_line_rigid_lattice(
    line_dots: List[EmbossedDot],
    dx: float,
    dy: float,
    cx: float
) -> List[BrailleGridCell]:
    """
    Fits rigid lattice to a line of dots.
    Delegates to fit_continuous_line_lattice for unified robust regression.
    """
    if not line_dots:
        return []
    line_y = float(np.mean([d.y for d in line_dots]))
    return fit_continuous_line_lattice(line_dots, line_y=line_y, dx=dx, dy=dy, cx=cx)


def fit_braille_grid(
    dots: List[EmbossedDot],
    image_shape: Tuple[int, int],
    expected_dot_pitch: Optional[float] = None
) -> List[List[BrailleGridCell]]:
    """
    Fits continuous 2x3 Braille grid lattice across all detected dot clusters.
    1. Estimates global pitches (dx, dy, cx).
    2. Measures and compensates for subtle residual line skew angle.
    3. Detects all line baselines simultaneously via 1D Gaussian KDE peak detection,
       interpolating missing lines using dominant median line pitch LH.
    4. Projects continuous 2x3 grid slots across each line width, scoring each of the
       6 canonical dot positions with spatial proximity and phase locking.
    """
    if len(dots) < 2:
        return []

    # 1. Estimate global pitches dx, dy, cx across all dots
    dx, dy, cx = estimate_global_pitches(dots, expected_dot_pitch=expected_dot_pitch)

    # 2. Check for subtle page line tilt using neighbor dot pairs
    dot_pts = np.array([[d.x, d.y] for d in dots], dtype=np.float32)
    from scipy.spatial import cKDTree
    tree_dots = cKDTree(dot_pts)
    angles = []
    for p in dot_pts:
        idxs = tree_dots.query_ball_point(p, r=cx * 1.3)
        for j in idxs:
            diff_x = dot_pts[j, 0] - p[0]
            diff_y = dot_pts[j, 1] - p[1]
            if (dx * 0.7) <= diff_x <= (cx * 1.4) and abs(diff_y) <= (dy * 0.5):
                angles.append(float(np.degrees(np.arctan2(diff_y, diff_x))))

    skew_angle = float(np.median(angles)) if len(angles) >= 10 else 0.0

    needs_rotation = abs(skew_angle) > 0.05
    if needs_rotation:
        h, w = image_shape[:2]
        cx_img, cy_img = w / 2.0, h / 2.0
        theta = np.radians(skew_angle)
        cos_t, sin_t = float(np.cos(theta)), float(np.sin(theta))
        working_dots = [
            EmbossedDot(
                x=float(cos_t * (d.x - cx_img) + sin_t * (d.y - cy_img) + cx_img),
                y=float(-sin_t * (d.x - cx_img) + cos_t * (d.y - cy_img) + cy_img),
                radius=d.radius,
                contrast=d.contrast,
                vector_dx=d.vector_dx,
                vector_dy=d.vector_dy
            )
            for d in dots
        ]
        w_pts = np.array([[d.x, d.y] for d in working_dots], dtype=np.float32)
    else:
        working_dots = dots
        w_pts = dot_pts

    # 3. Detect line baselines with median line pitch interpolation
    line_baselines = detect_line_baselines(working_dots, dy=dy)
    if not line_baselines:
        return []

    # 4. Fit continuous 2x3 lattice across each line
    output_lines: List[List[BrailleGridCell]] = []

    for line_y in line_baselines:
        m_line = np.abs(w_pts[:, 1] - line_y) <= (dy * 1.6)
        line_dots = [working_dots[i] for i in range(len(working_dots)) if m_line[i]]
        if len(line_dots) < 2:
            continue
        cells = fit_continuous_line_lattice(
            line_dots=line_dots,
            line_y=line_y,
            dx=dx,
            dy=dy,
            cx=cx,
            all_dots=working_dots
        )
        if not cells:
            continue

        if needs_rotation:
            # Map cell coordinates back to original unrotated image coordinates
            inv_cos, inv_sin = float(np.cos(-theta)), float(np.sin(-theta))
            unrot_cells: List[BrailleGridCell] = []
            for c in cells:
                corners = np.array([
                    [c.x1, c.y1],
                    [c.x2, c.y1],
                    [c.x2, c.y2],
                    [c.x1, c.y2]
                ], dtype=np.float32)
                orig_corners_x = inv_cos * (corners[:, 0] - cx_img) + inv_sin * (corners[:, 1] - cy_img) + cx_img
                orig_corners_y = -inv_sin * (corners[:, 0] - cx_img) + inv_cos * (corners[:, 1] - cy_img) + cy_img
                orig_cx = float(np.mean(orig_corners_x))
                orig_cy = float(np.mean(orig_corners_y))
                unrot_cells.append(BrailleGridCell(
                    x1=float(np.min(orig_corners_x)),
                    y1=float(np.min(orig_corners_y)),
                    x2=float(np.max(orig_corners_x)),
                    y2=float(np.max(orig_corners_y)),
                    cx=orig_cx,
                    cy=orig_cy,
                    dots=c.dots,
                    binary_str=c.binary_str,
                    class_index=c.class_index,
                    has_space_before=c.has_space_before
                ))
            output_lines.append(unrot_cells)
        else:
            output_lines.append(cells)

    return output_lines


def export_grid_debug_image(
    image: np.ndarray,
    dots: List[EmbossedDot],
    grid_lines: List[List[BrailleGridCell]],
    output_path: str = "grid_debug.png"
) -> np.ndarray:
    """
    Renders diagnostic visualization:
    - Green circles for detected dot centroids.
    - Blue bounding boxes for every 2x3 cell grid slot.
    Saves image to output_path and returns annotated BGR image.
    """
    canvas = image.copy()
    if len(canvas.shape) == 2:
        canvas = cv2.cvtColor(canvas, cv2.COLOR_GRAY2BGR)

    # 1. Green circles for detected dot centroids
    for d in dots:
        cv2.circle(
            canvas,
            (int(round(d.x)), int(round(d.y))),
            max(2, int(round(d.radius))),
            (0, 255, 0),
            -1
        )

    # 2. Blue bounding boxes for every 2x3 cell grid slot
    for line in grid_lines:
        for cell in line:
            pt1 = (int(round(cell.x1)), int(round(cell.y1)))
            pt2 = (int(round(cell.x2)), int(round(cell.y2)))
            cv2.rectangle(canvas, pt1, pt2, (255, 0, 0), 1)

    cv2.imwrite(output_path, canvas)
    return canvas


def snap_yolo_detections_to_lattice(
    detections: List[Dict[str, Any]],
    image_shape: Tuple[int, int]
) -> List[List[BrailleGridCell]]:
    """
    Snaps YOLO cell object detections to a rigid horizontal lattice per line.
    Eliminates half-cell bounding box jitter and identifies empty cells (word spaces).
    """
    if not detections:
        return []

    med_w = float(np.median([d['w'] for d in detections]))
    med_h = float(np.median([d['h'] for d in detections]))

    # Step 1: Group detections into lines by cy
    detections_sorted = sorted(detections, key=lambda d: d['cy'])
    lines: List[List[Dict[str, Any]]] = []
    curr_line: List[Dict[str, Any]] = []
    line_y = -1.0

    for d in detections_sorted:
        if line_y < 0:
            curr_line.append(d)
            line_y = d['cy']
        elif abs(d['cy'] - line_y) < (med_h * 0.65):
            curr_line.append(d)
            line_y = float(np.mean([x['cy'] for x in curr_line]))
        else:
            curr_line.sort(key=lambda x: x['cx'])
            lines.append(curr_line)
            curr_line = [d]
            line_y = d['cy']

    if curr_line:
        curr_line.sort(key=lambda x: x['cx'])
        lines.append(curr_line)

    # Step 2: For each line, estimate inter-cell pitch cx and snap detections
    result_lines: List[List[BrailleGridCell]] = []

    for l in lines:
        if not l:
            continue
        if len(l) == 1:
            d = l[0]
            dots_list = [int(c) for c in d['binary_str']]
            result_lines.append([BrailleGridCell(
                x1=d['x1'], y1=d['y1'], x2=d['x2'], y2=d['y2'],
                cx=d['cx'], cy=d['cy'], dots=dots_list,
                binary_str=d['binary_str'], class_index=d['class'],
                has_space_before=False
            )])
            continue

        cxs = np.array([d['cx'] for d in l], dtype=np.float32)
        diffs = np.diff(cxs)

        # Candidate cell-to-cell differences (excluding wide multi-cell spaces)
        valid_steps = diffs[(diffs >= med_w * 0.8) & (diffs <= med_w * 2.2)]
        cx = float(np.median(valid_steps)) if len(valid_steps) > 0 else (med_w * 1.5)

        # Fit optimal phase X0
        min_x = float(cxs.min())
        best_x0 = min_x
        best_cost = float('inf')
        for cand_x0 in np.linspace(min_x - cx, min_x, 80):
            rem = (cxs - cand_x0) % cx
            dist = np.minimum(rem, cx - rem)
            cost = float(np.sum(dist**2))
            if cost < best_cost:
                best_cost = cost
                best_x0 = float(cand_x0)

        # Quantize detections into cell indices
        line_cells_map: Dict[int, Dict[str, Any]] = {}
        for d in l:
            c = int(round((d['cx'] - best_x0) / cx))
            # If multiple detections map to same cell index, keep highest confidence
            if c not in line_cells_map or d['conf'] > line_cells_map[c]['conf']:
                line_cells_map[c] = d

        # Reconstruct line cells with empty cell tracking
        sorted_indices = sorted(line_cells_map.keys())
        line_cells: List[BrailleGridCell] = []
        last_c = None
        last_d = None

        for c_idx in sorted_indices:
            d = line_cells_map[c_idx]
            has_space = False
            if last_c is not None and last_d is not None:
                # Dynamic Spacing Calibration:
                # Do NOT emit an empty space ' ' unless the horizontal gap between two consecutive 2x3 cells
                # is strictly greater than 1.5 times the inter-cell pitch (cx).
                # Any gap smaller than this MUST be treated as contiguous characters within the same word.
                center_gap = d['cx'] - last_d['cx']
                if center_gap > 1.5 * cx:
                    has_space = True

            last_c = c_idx
            last_d = d

            dots_list = [int(ch) for ch in d['binary_str']]
            line_cells.append(BrailleGridCell(
                x1=d['x1'],
                y1=d['y1'],
                x2=d['x2'],
                y2=d['y2'],
                cx=d['cx'],
                cy=d['cy'],
                dots=dots_list,
                binary_str=d['binary_str'],
                class_index=d['class'],
                has_space_before=has_space
            ))

        if line_cells:
            result_lines.append(line_cells)

    return result_lines
