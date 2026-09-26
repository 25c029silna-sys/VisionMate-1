"""
Braille Cell Segmentation Module.
Groups detected dots into 2x3 Braille cells without assuming a uniform global grid:
- Estimates intra-cell dot pitches (dx, dy) and inter-cell pitch (cx)
- Corrects residual page line skew angle
- Detects reading line baselines via 1D Gaussian KDE peak detection with interpolation
- Fits continuous 2x3 canonical lattices per line
- Extracts 6-dot boolean pattern [dot1, dot2, dot3, dot4, dot5, dot6] with dot confidences
"""

import cv2
import numpy as np
from typing import List, Tuple, Dict, Any, Optional
from dataclasses import dataclass, field
from scipy.spatial import cKDTree
from scipy.signal import find_peaks

# Column-major Braille 2x3 Grid Mapping
# Col 0 (left):   (Row 0, Col 0) -> Dot 1, (Row 1, Col 0) -> Dot 2, (Row 2, Col 0) -> Dot 3
# Col 1 (right):  (Row 0, Col 1) -> Dot 4, (Row 1, Col 1) -> Dot 5, (Row 2, Col 1) -> Dot 6
GRID_COORDS_TO_DOT_NUM: Dict[Tuple[int, int], int] = {
    (0, 0): 1,
    (1, 0): 2,
    (2, 0): 3,
    (0, 1): 4,
    (1, 1): 5,
    (2, 1): 6,
}

DOT_NUM_TO_GRID_COORDS: Dict[int, Tuple[int, int]] = {
    v: k for k, v in GRID_COORDS_TO_DOT_NUM.items()
}


@dataclass
class BrailleCellCandidate:
    cell_index: int
    line_index: int
    x1: float
    y1: float
    x2: float
    y2: float
    cx: float
    cy: float
    dots: List[int]                # [d1, d2, d3, d4, d5, d6], each 0 or 1
    binary_str: str                # e.g. "110011"
    class_index: int               # 0..63
    confidence: float              # Overall cell confidence [0.0..1.0]
    dot_confidences: List[float]   # 6 float confidences for dots 1..6
    has_space_before: bool         # True if inter-word gap precedes this cell
    canonical_coords: List[Tuple[float, float]] = field(default_factory=list) # 6 (x,y) sites

    def to_dict(self) -> Dict[str, Any]:
        return {
            "cell_index": self.cell_index,
            "line_index": self.line_index,
            "x1": round(self.x1, 2),
            "y1": round(self.y1, 2),
            "x2": round(self.x2, 2),
            "y2": round(self.y2, 2),
            "cx": round(self.cx, 2),
            "cy": round(self.cy, 2),
            "pattern": list(self.dots),
            "binary_str": self.binary_str,
            "class_index": self.class_index,
            "confidence": round(self.confidence, 4),
            "dot_confidences": [round(c, 4) for c in self.dot_confidences],
            "has_space_before": self.has_space_before,
            "canonical_coords": [(round(x, 2), round(y, 2)) for (x, y) in self.canonical_coords]
        }


def estimate_pitches(
    dots: List[Dict[str, Any]],
    expected_dot_pitch: Optional[float] = None
) -> Tuple[float, float, float]:
    """
    Estimates global horizontal dot pitch (dx), vertical dot pitch (dy),
    and inter-cell pitch (cx) from pairwise nearest neighbor distributions.
    Standard Braille proportions: dy ≈ dx, cx ≈ 2.5 * dx to 3.2 * dx.
    """
    if len(dots) < 4:
        pitch = expected_dot_pitch or 14.0
        return pitch, pitch, pitch * 2.8

    pts = np.array([[d["x"], d["y"]] for d in dots], dtype=np.float32)
    tree = cKDTree(pts)
    nn_dists, _ = tree.query(pts, k=min(6, len(pts)))

    # 1. Intra-cell dot pitch dy from close neighbors
    valid_nn = nn_dists[:, 1][(nn_dists[:, 1] >= 6.0) & (nn_dists[:, 1] <= 32.0)]
    if len(valid_nn) > 0:
        base_pitch = float(np.median(valid_nn))
    else:
        base_pitch = expected_dot_pitch or 14.0

    # 2. X and Y pairwise projections
    n_sample = min(len(pts), 400)
    indices = np.random.choice(len(pts), size=n_sample, replace=False) if len(pts) > n_sample else np.arange(len(pts))
    sample_pts = pts[indices]

    dxs = []
    dys = []
    cxs = []

    for i in range(len(sample_pts)):
        d_vec = np.abs(sample_pts[i+1:] - sample_pts[i])
        if len(d_vec) == 0:
            continue
        # Intra-cell vertical pairs: small dx, dy ~ base_pitch
        v_pairs = d_vec[(d_vec[:, 0] <= base_pitch * 0.45) & (d_vec[:, 1] >= base_pitch * 0.70) & (d_vec[:, 1] <= base_pitch * 1.35)]
        if len(v_pairs) > 0:
            dys.extend(v_pairs[:, 1])

        # Intra-cell horizontal pairs: dx ~ base_pitch, small dy
        h_pairs = d_vec[(d_vec[:, 0] >= base_pitch * 0.70) & (d_vec[:, 0] <= base_pitch * 1.35) & (d_vec[:, 1] <= base_pitch * 0.45)]
        if len(h_pairs) > 0:
            dxs.extend(h_pairs[:, 0])

        # Inter-cell pairs: dx ~ 2.4 - 3.4 * base_pitch, small dy
        cell_pairs = d_vec[(d_vec[:, 0] >= base_pitch * 2.2) & (d_vec[:, 0] <= base_pitch * 3.6) & (d_vec[:, 1] <= base_pitch * 0.50)]
        if len(cell_pairs) > 0:
            cxs.extend(cell_pairs[:, 0])

    dx = float(np.median(dxs)) if len(dxs) >= 3 else base_pitch
    dy = float(np.median(dys)) if len(dys) >= 3 else base_pitch
    cx = float(np.median(cxs)) if len(cxs) >= 3 else (dx * 2.85)

    return dx, dy, cx


def estimate_line_skew(
    dots: List[Dict[str, Any]],
    dx: float,
    dy: float,
    cx: float
) -> float:
    """
    Estimates residual page tilt / reading line angle in degrees using neighboring horizontal pairs.
    """
    if len(dots) < 6:
        return 0.0

    pts = np.array([[d["x"], d["y"]] for d in dots], dtype=np.float32)
    tree = cKDTree(pts)
    angles = []

    for p in pts:
        idxs = tree.query_ball_point(p, r=cx * 1.3)
        for j in idxs:
            diff = pts[j] - p
            if (dx * 0.70) <= diff[0] <= (cx * 1.50) and abs(diff[1]) <= (dy * 0.50):
                ang = np.degrees(np.arctan2(diff[1], diff[0]))
                angles.append(ang)

    if angles:
        return float(np.median(angles))
    return 0.0


def detect_line_baselines(
    y_coords: np.ndarray,
    dy: float
) -> List[float]:
    """
    Detects reading line Y centers via 1D Gaussian Kernel Density Estimation (KDE)
    and interpolates missing lines based on dominant median line height (LH).
    """
    if len(y_coords) < 3:
        return [float(np.mean(y_coords))] if len(y_coords) > 0 else []

    y_min, y_max = float(y_coords.min()), float(y_coords.max())
    y_grid = np.arange(y_min - dy, y_max + dy, 1.0, dtype=np.float32)
    density = np.zeros_like(y_grid)
    sigma = max(4.0, dy * 0.70)

    for y in y_coords:
        density += np.exp(-0.5 * ((y_grid - y) / sigma)**2)

    min_dist_samples = max(int(round(dy * 2.8)), 14)
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

    # Dominant line pitch LH
    diffs = np.diff(raw_lines)
    valid_diffs = diffs[(diffs >= dy * 2.5) & (diffs <= dy * 8.0)]
    med_lh = float(np.median(valid_diffs)) if len(valid_diffs) > 0 else float(np.median(diffs))

    # Interpolate missing lines where gap >= 1.6 * med_lh
    interpolated: List[float] = [raw_lines[0]]
    for i in range(len(raw_lines) - 1):
        y_curr = raw_lines[i]
        y_next = raw_lines[i + 1]
        gap = y_next - y_curr
        num_missing = int(round(gap / med_lh)) - 1
        if num_missing >= 1:
            step_lh = gap / float(num_missing + 1)
            for m in range(1, num_missing + 1):
                interpolated.append(y_curr + (m * step_lh))
        interpolated.append(y_next)

    interpolated.sort()
    return interpolated


def segment_dots_into_cells(
    dots: List[Dict[str, Any]],
    image_shape: Tuple[int, int],
    relief_map: Optional[np.ndarray] = None
) -> List[List[BrailleCellCandidate]]:
    """
    Complete Braille cell segmentation:
    1. Estimate global pitches (dx, dy, cx).
    2. Compensate for residual line skew.
    3. Detect reading line baselines.
    4. Fit continuous 2x3 lattice for each line, resolving 6 canonical positions:
       [d1, d2, d3, d4, d5, d6].
    5. Detect word spaces (has_space_before).
    6. Return lines of BrailleCellCandidate objects.
    """
    if len(dots) < 2:
        return []

    h, w = image_shape[:2]
    dx, dy, cx = estimate_pitches(dots)
    skew_angle = estimate_line_skew(dots, dx, dy, cx)

    pts = np.array([[d["x"], d["y"]] for d in dots], dtype=np.float32)
    dot_contrasts = np.array([d.get("contrast", 20.0) for d in dots], dtype=np.float32)

    # Rotate coordinates if skew is notable (|skew| > 0.05 deg)
    needs_rotation = abs(skew_angle) > 0.05
    cx_img, cy_img = w / 2.0, h / 2.0

    if needs_rotation:
        theta = np.radians(skew_angle)
        cos_t, sin_t = np.cos(theta), np.sin(theta)
        x_rot = cos_t * (pts[:, 0] - cx_img) + sin_t * (pts[:, 1] - cy_img) + cx_img
        y_rot = -sin_t * (pts[:, 0] - cx_img) + cos_t * (pts[:, 1] - cy_img) + cy_img
        pts_working = np.column_stack([x_rot, y_rot])
    else:
        pts_working = pts.copy()

    tree_working = cKDTree(pts_working)

    # Detect lines along rotated Y coordinates
    lines_y = detect_line_baselines(pts_working[:, 1], dy=dy)

    node_tol = dx * 0.46
    ambiguous_tol = dx * 0.62

    grid_lines: List[List[BrailleCellCandidate]] = []
    global_cell_idx = 0

    for line_idx, line_y in enumerate(lines_y):
        mask = np.abs(pts_working[:, 1] - line_y) <= (dy * 1.50)
        line_pts = pts_working[mask]
        if len(line_pts) < 2:
            continue

        xs = line_pts[:, 0]
        ys = line_pts[:, 1]

        # Fit Row 0 baseline Y0
        cand_y0s = np.linspace(line_y - dy, line_y + 0.3 * dy, 40)
        best_y0 = float(ys.min())
        best_cost_y = float('inf')
        for cand_y0 in cand_y0s:
            cost_y = 0.0
            for y in ys:
                r = int(round((y - cand_y0) / dy))
                if 0 <= r <= 2:
                    cost_y += (y - (cand_y0 + r * dy)) ** 2
                else:
                    cost_y += 30.0 * (dy ** 2)
            if cost_y < best_cost_y:
                best_cost_y = cost_y
                best_y0 = float(cand_y0)
        Y0 = best_y0

        # Fit horizontal phase X0
        min_x, max_x = float(xs.min()), float(xs.max())
        best_x0 = min_x
        best_cost_x = float('inf')
        for cand_x0 in np.linspace(min_x - cx, min_x, 100):
            rem = (xs - cand_x0) % cx
            d0 = np.minimum(rem, cx - rem)
            d1 = np.abs(rem - dx)
            cost_x = float(np.sum(np.minimum(d0, d1) ** 2))
            if cost_x < best_cost_x:
                best_cost_x = cost_x
                best_x0 = float(cand_x0)

        c_start = int(round((min_x - best_x0) / cx))
        c_end = int(round((max_x - best_x0) / cx))

        line_cells: List[BrailleCellCandidate] = []
        consecutive_empty = 0
        last_non_empty_cx = None

        for c in range(c_start, c_end + 1):
            col0_x = best_x0 + c * cx
            col1_x = col0_x + dx

            # 6 canonical dot positions in working space
            # Col 0: (Row 0, Col 0), (Row 1, Col 0), (Row 2, Col 0) -> Dots 1, 2, 3
            # Col 1: (Row 0, Col 1), (Row 1, Col 1), (Row 2, Col 1) -> Dots 4, 5, 6
            canonical_nodes_rot = [
                (col0_x, Y0),              # Dot 1
                (col0_x, Y0 + dy),         # Dot 2
                (col0_x, Y0 + 2.0 * dy),   # Dot 3
                (col1_x, Y0),              # Dot 4
                (col1_x, Y0 + dy),         # Dot 5
                (col1_x, Y0 + 2.0 * dy),   # Dot 6
            ]

            dots_present = [0, 0, 0, 0, 0, 0]
            dot_confs = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

            for dot_i, (nx_r, ny_r) in enumerate(canonical_nodes_rot):
                dist, nn_idx = tree_working.query([nx_r, ny_r], k=1)
                nn_contrast = float(dot_contrasts[nn_idx]) if nn_idx < len(dot_contrasts) else 0.0

                if dist <= node_tol:
                    dots_present[dot_i] = 1
                    dot_confs[dot_i] = min(1.0, float(1.0 - (dist / node_tol) * 0.3) * (nn_contrast / 30.0))
                elif dist <= ambiguous_tol and relief_map is not None:
                    # Check relief map in original coordinates
                    if needs_rotation:
                        inv_cos, inv_sin = float(np.cos(-theta)), float(np.sin(-theta))
                        orig_x = inv_cos * (nx_r - cx_img) + inv_sin * (ny_r - cy_img) + cx_img
                        orig_y = -inv_sin * (nx_r - cx_img) + inv_cos * (ny_r - cy_img) + cy_img
                    else:
                        orig_x, orig_y = nx_r, ny_r
                    ix, iy = int(round(orig_x)), int(round(orig_y))
                    if 0 <= ix < w and 0 <= iy < h and relief_map[iy, ix] >= 7.0:
                        dots_present[dot_i] = 1
                        dot_confs[dot_i] = 0.55

            is_empty = (sum(dots_present) == 0)
            if is_empty:
                consecutive_empty += 1
                continue

            # Bounding box in working space
            bx1_r = col0_x - 0.25 * dx
            by1_r = Y0 - 0.25 * dy
            bx2_r = col1_x + 0.25 * dx
            by2_r = Y0 + 2.25 * dy

            # Transform bounding box & canonical sites back to image space
            if needs_rotation:
                inv_cos, inv_sin = float(np.cos(-theta)), float(np.sin(-theta))
                corners_rot = np.array([
                    [bx1_r, by1_r], [bx2_r, by1_r], [bx2_r, by2_r], [bx1_r, by2_r]
                ])
                oxs = inv_cos * (corners_rot[:, 0] - cx_img) + inv_sin * (corners_rot[:, 1] - cy_img) + cx_img
                oys = -inv_sin * (corners_rot[:, 0] - cx_img) + inv_cos * (corners_rot[:, 1] - cy_img) + cy_img
                cell_x1, cell_y1 = float(np.min(oxs)), float(np.min(oys))
                cell_x2, cell_y2 = float(np.max(oxs)), float(np.max(oys))
                cell_cx, cell_cy = float(np.mean(oxs)), float(np.mean(oys))

                # Canonical node sites in image space
                canon_img = []
                for (nx_r, ny_r) in canonical_nodes_rot:
                    cn_x = inv_cos * (nx_r - cx_img) + inv_sin * (ny_r - cy_img) + cx_img
                    cn_y = -inv_sin * (nx_r - cx_img) + inv_cos * (ny_r - cy_img) + cy_img
                    canon_img.append((float(cn_x), float(cn_y)))
            else:
                cell_x1, cell_y1 = float(bx1_r), float(by1_r)
                cell_x2, cell_y2 = float(bx2_r), float(by2_r)
                cell_cx, cell_cy = float((bx1_r + bx2_r) / 2.0), float((by1_r + by2_r) / 2.0)
                canon_img = [(float(x), float(y)) for (x, y) in canonical_nodes_rot]

            # Inter-word space check
            has_space_before = False
            if last_non_empty_cx is not None:
                gap = cell_cx - last_non_empty_cx
                if gap > 1.55 * cx or consecutive_empty >= 1:
                    has_space_before = True

            last_non_empty_cx = cell_cx
            consecutive_empty = 0

            bin_str = "".join(str(b) for b in dots_present)
            cls_idx = sum(b * (32 >> i) for i, b in enumerate(dots_present))
            active_confs = [c for c, d in zip(dot_confs, dots_present) if d == 1]
            cell_conf = float(np.mean(active_confs)) if active_confs else 0.50

            candidate = BrailleCellCandidate(
                cell_index=global_cell_idx,
                line_index=line_idx,
                x1=cell_x1,
                y1=cell_y1,
                x2=cell_x2,
                y2=cell_y2,
                cx=cell_cx,
                cy=cell_cy,
                dots=dots_present,
                binary_str=bin_str,
                class_index=cls_idx,
                confidence=cell_conf,
                dot_confidences=dot_confs,
                has_space_before=has_space_before,
                canonical_coords=canon_img
            )

            line_cells.append(candidate)
            global_cell_idx += 1

        if line_cells:
            grid_lines.append(line_cells)

    return grid_lines
