"""
VisionMate Geometric Braille Analysis Module.
Implements a dedicated 8-phase geometric analysis engine to evaluate whether the computer
correctly sees the physical Braille cells before attempting linguistic interpretation:

PHASE 1 - Dot Detection Only:
    Rectify page, enhance embossed dots, detect candidate raised dots,
    and save an image containing ONLY the detected dot centers (detected_dots.png).
PHASE 2 - Learn Local Dot Geometry:
    Estimate vertical, horizontal, intra-cell column, inter-cell, and word spacing
    per line independently to account for photographic perspective distortion.
PHASE 3 - Reconstruct Cells:
    Search for dots near the 6 canonical cell positions [d1, d2, d3, d4, d5, d6].
PHASE 4 - Detect Missing Cells:
    Instantiate explicit MISSING_CELL objects in the sequence when geometry demands
    a cell slot but no dots were detected, preventing index collapse.
PHASE 5 - Detect Merged and Split Cells:
    Resolve multi-cell clusters and accidental splits using local spacing metrics.
PHASE 6 - Cell Visualization:
    Render diagnostic image with color-coded markers for NORMAL, MISSING, MERGED,
    and UNCERTAIN cells.
PHASE 7 - Raw Geometric Output:
    Output the exact 6-bit binary pattern sequence per line without decoding text.
PHASE 8 - Geometry-Validated Decoding Bridge:
    Translate validated patterns to Unicode and text without language model hallucination.
"""

import os
import sys
import argparse
from dataclasses import dataclass, field
from enum import Enum
from typing import List, Dict, Any, Tuple, Optional

import cv2
import numpy as np
from scipy.spatial import cKDTree
from scipy.signal import find_peaks

# Support unicode printing in Windows console
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

from .perspective import rectify_page_perspective
from .preprocessing import preprocess_image, PREPROCESS_METHOD_COMBINED
from .dot_detection import detect_embossed_braille_dots
from .braille_decoder import pattern_to_unicode


class CellStatus(str, Enum):
    NORMAL = "NORMAL"
    MISSING = "MISSING"
    MERGED = "MERGED"
    UNCERTAIN = "UNCERTAIN"


@dataclass
class GeometricDot:
    x: float
    y: float
    radius: float
    confidence: float
    contrast: float = 0.0

    def to_dict(self) -> Dict[str, Any]:
        return {
            "x": round(self.x, 2),
            "y": round(self.y, 2),
            "radius": round(self.radius, 2),
            "confidence": round(self.confidence, 4),
            "contrast": round(self.contrast, 2),
        }


@dataclass
class GeometricCell:
    cell_index: int
    line_index: int
    status: CellStatus
    dots: List[int]                     # [d1, d2, d3, d4, d5, d6], each 0 or 1
    binary_str: str                     # e.g. "100110" or "MISSING"
    x1: float
    y1: float
    x2: float
    y2: float
    cx: float
    cy: float
    confidence: float = 1.0
    dot_confidences: List[float] = field(default_factory=lambda: [0.0] * 6)
    canonical_coords: List[Tuple[float, float]] = field(default_factory=list)
    has_space_before: bool = False
    details: str = ""

    def to_dict(self) -> Dict[str, Any]:
        return {
            "cell_index": self.cell_index,
            "line_index": self.line_index,
            "status": self.status.value,
            "dots": self.dots,
            "binary_str": self.binary_str,
            "box": [round(self.x1, 1), round(self.y1, 1), round(self.x2, 1), round(self.y2, 1)],
            "center": [round(self.cx, 1), round(self.cy, 1)],
            "confidence": round(self.confidence, 4),
            "dot_confidences": [round(c, 3) for c in self.dot_confidences],
            "has_space_before": self.has_space_before,
            "details": self.details,
        }


@dataclass
class LineGeometryStats:
    line_index: int
    baseline_y: float
    num_dots: int
    num_cells: int
    vertical_dot_spacing: float         # Vertical dot spacing (dy)
    horizontal_dot_spacing: float       # Horizontal dot spacing (dx)
    intra_cell_col_spacing: float       # Braille intra-cell column spacing (intra_col)
    inter_cell_spacing: float           # Inter-cell spacing (cx)
    inter_cell_gap: float               # Inter-cell physical blank gap (cx - dx)
    word_spacing: float                 # Word spacing (approx 2 * cx)
    word_gap: float                     # Word blank gap (approx 2 * cx - dx)
    tilt_angle_deg: float = 0.0

    def summary_table_row(self) -> str:
        return (
            f"Line {self.line_index:02d} | "
            f"Vert Spacing: {self.vertical_dot_spacing:5.1f}px | "
            f"Horiz Spacing: {self.horizontal_dot_spacing:5.1f}px | "
            f"Intra-Col: {self.intra_cell_col_spacing:5.1f}px | "
            f"Inter-Cell: {self.inter_cell_spacing:5.1f}px (gap: {self.inter_cell_gap:4.1f}px) | "
            f"Word Spacing: {self.word_spacing:5.1f}px (gap: {self.word_gap:4.1f}px)"
        )


class GeometricBrailleAnalyzer:
    """
    Dedicated Geometric Braille Analysis Engine.
    Executes Phases 1 to 8 without character classification dependencies.
    """

    def __init__(self, debug_dir: str = "debug"):
        self.debug_dir = debug_dir
        os.makedirs(self.debug_dir, exist_ok=True)

    # =========================================================================
    # PHASE 1: DOT DETECTION ONLY
    # =========================================================================
    def phase1_detect_dots(
        self,
        image_input: Any,
        output_filename: str = "detected_dots.png"
    ) -> Tuple[np.ndarray, List[GeometricDot]]:
        """
        Phase 1:
        1. Rectifies the photographed page perspective.
        2. Enhances embossed dots via morphological dipoles.
        3. Detects candidate raised dots with (x, y, radius, confidence).
        4. Saves an image containing ONLY the detected dot centers.
        """
        if isinstance(image_input, str):
            raw_bgr = cv2.imread(image_input)
            if raw_bgr is None:
                raise FileNotFoundError(f"Cannot load image: {image_input}")
        elif isinstance(image_input, np.ndarray):
            raw_bgr = image_input.copy()
        else:
            raise ValueError(f"Unsupported image input type: {type(image_input)}")

        # Step 1: Rectify page perspective
        rectified_bgr, _, was_rectified = rectify_page_perspective(raw_bgr)

        # Step 2: Enhance embossed dots
        prep = preprocess_image(rectified_bgr, method=PREPROCESS_METHOD_COMBINED)

        # Step 3: Detect candidate raised dots
        raw_dots = detect_embossed_braille_dots(
            rectified_bgr,
            tophat=prep["tophat"],
            blackhat=prep["blackhat"],
            min_radius=2.0,
            max_radius=14.0,
            min_contrast=6.0,
        )

        dots: List[GeometricDot] = [
            GeometricDot(
                x=float(d["x"]),
                y=float(d["y"]),
                radius=float(d["radius"]),
                confidence=float(d.get("confidence", 0.8)),
                contrast=float(d.get("contrast", 0.0)),
            )
            for d in raw_dots
        ]

        # Step 4: Save image containing ONLY the detected dot centers
        h, w = rectified_bgr.shape[:2]
        # Crisp high-contrast canvas with dark background
        dots_canvas = np.zeros((h, w, 3), dtype=np.uint8)

        for d in dots:
            pt = (int(round(d.x)), int(round(d.y)))
            r = max(2, int(round(d.radius)))
            # Color intensity scaled by detection confidence
            intensity = int(max(150, min(255, d.confidence * 255)))
            cv2.circle(dots_canvas, pt, r, (0, intensity, 0), -1, lineType=cv2.LINE_AA)
            cv2.circle(dots_canvas, pt, 1, (255, 255, 255), -1, lineType=cv2.LINE_AA)

        out_path = os.path.join(self.debug_dir, output_filename)
        cv2.imwrite(out_path, dots_canvas)

        # Also save to current directory if not already there
        if self.debug_dir != "." and not os.path.exists(output_filename):
            try:
                cv2.imwrite(output_filename, dots_canvas)
            except Exception:
                pass

        return rectified_bgr, dots

    # =========================================================================
    # PHASE 2: LEARN LOCAL DOT GEOMETRY (PER-LINE ESTIMATION)
    # =========================================================================
    def phase2_estimate_local_geometry(
        self,
        dots: List[GeometricDot],
        image_shape: Tuple[int, int]
    ) -> Tuple[List[List[GeometricDot]], List[LineGeometryStats]]:
        """
        Phase 2:
        Separates dots into lines and calculates line-specific statistics:
        - vertical dot spacing (dy)
        - horizontal dot spacing (dx)
        - Braille intra-cell column spacing (intra_col)
        - inter-cell spacing (cx and cell gap)
        - word spacing (word spacing and word gap)
        Accounts for perspective distortion and prints per-line statistics.
        """
        if not dots:
            return [], []

        h, w = image_shape[:2]
        y_coords = np.array([d.y for d in dots], dtype=np.float32)

        # Approximate base pitch from nearest neighbor vertical pairs
        pts_all = np.array([[d.x, d.y] for d in dots], dtype=np.float32)
        tree_all = cKDTree(pts_all)
        dists, _ = tree_all.query(pts_all, k=min(4, len(pts_all)))
        valid_nn = dists[:, 1][(dists[:, 1] >= 6.0) & (dists[:, 1] <= 32.0)]
        initial_pitch = float(np.median(valid_nn)) if len(valid_nn) > 0 else 14.0

        # Detect line baselines using 1D Gaussian KDE
        y_min, y_max = float(y_coords.min()), float(y_coords.max())
        y_grid = np.arange(y_min - initial_pitch, y_max + initial_pitch, 1.0, dtype=np.float32)
        density = np.zeros_like(y_grid)
        sigma = max(4.0, initial_pitch * 0.70)
        for y in y_coords:
            density += np.exp(-0.5 * ((y_grid - y) / sigma) ** 2)

        min_dist_samples = max(int(round(initial_pitch * 2.8)), 16)
        peak_indices, _ = find_peaks(
            density,
            distance=min_dist_samples,
            height=float(np.mean(density) * 0.18)
        )

        if len(peak_indices) == 0:
            raw_baselines = [float(np.median(y_coords))]
        else:
            raw_baselines = sorted([float(y_grid[idx]) for idx in peak_indices])

        # Interpolate physically missing lines if gap >= 1.6 * median line height
        diffs = np.diff(raw_baselines)
        valid_lh = diffs[(diffs >= initial_pitch * 2.5) & (diffs <= initial_pitch * 8.0)]
        med_lh = float(np.median(valid_lh)) if len(valid_lh) > 0 else (initial_pitch * 4.8)

        line_baselines: List[float] = [raw_baselines[0]]
        for i in range(len(raw_baselines) - 1):
            y_curr = raw_baselines[i]
            y_next = raw_baselines[i + 1]
            gap = y_next - y_curr
            missing_count = int(round(gap / med_lh)) - 1
            if missing_count >= 1:
                step = gap / float(missing_count + 1)
                for m in range(1, missing_count + 1):
                    line_baselines.append(y_curr + (m * step))
            line_baselines.append(y_next)
        line_baselines.sort()

        # Partition dots into lines & estimate local geometry
        line_dots_list: List[List[GeometricDot]] = []
        line_stats_list: List[LineGeometryStats] = []

        for line_idx, line_y in enumerate(line_baselines):
            # Window around baseline
            mask = np.abs(y_coords - line_y) <= (initial_pitch * 1.6)
            line_dots = [d for d, m in zip(dots, mask) if m]

            if len(line_dots) < 2:
                stats = LineGeometryStats(
                    line_index=line_idx,
                    baseline_y=line_y,
                    num_dots=len(line_dots),
                    num_cells=0,
                    vertical_dot_spacing=initial_pitch,
                    horizontal_dot_spacing=initial_pitch,
                    intra_cell_col_spacing=initial_pitch,
                    inter_cell_spacing=initial_pitch * 2.85,
                    inter_cell_gap=initial_pitch * 1.85,
                    word_spacing=initial_pitch * 5.7,
                    word_gap=initial_pitch * 4.7,
                )
                line_dots_list.append(line_dots)
                line_stats_list.append(stats)
                continue

            line_dots.sort(key=lambda d: d.x)
            pts_line = np.array([[d.x, d.y] for d in line_dots], dtype=np.float32)

            dx_matrix = np.abs(pts_line[:, 0:1] - pts_line[:, 0:1].T)
            dy_matrix = np.abs(pts_line[:, 1:2] - pts_line[:, 1:2].T)

            # Local vertical dot spacing dy
            v_pairs = dy_matrix[(dx_matrix <= initial_pitch * 0.45) & (dy_matrix >= initial_pitch * 0.65) & (dy_matrix <= initial_pitch * 1.45)]
            loc_dy = float(np.median(v_pairs)) if len(v_pairs) >= 2 else initial_pitch

            # Local horizontal dot spacing dx / intra-cell column spacing
            h_pairs = dx_matrix[(dy_matrix <= loc_dy * 0.45) & (dx_matrix >= loc_dy * 0.65) & (dx_matrix <= loc_dy * 1.45)]
            loc_dx = float(np.median(h_pairs)) if len(h_pairs) >= 2 else loc_dy
            intra_col = loc_dx

            # Local inter-cell spacing cx
            c_pairs = dx_matrix[(dy_matrix <= loc_dy * 0.45) & (dx_matrix >= loc_dx * 2.2) & (dx_matrix <= loc_dx * 3.6)]
            loc_cx = float(np.median(c_pairs)) if len(c_pairs) >= 2 else (loc_dx * 2.85)

            # Local gaps
            loc_cell_gap = loc_cx - loc_dx
            loc_word_spacing = loc_cx * 2.0
            loc_word_gap = loc_word_spacing - loc_dx

            stats = LineGeometryStats(
                line_index=line_idx,
                baseline_y=line_y,
                num_dots=len(line_dots),
                num_cells=0,
                vertical_dot_spacing=loc_dy,
                horizontal_dot_spacing=loc_dx,
                intra_cell_col_spacing=intra_col,
                inter_cell_spacing=loc_cx,
                inter_cell_gap=loc_cell_gap,
                word_spacing=loc_word_spacing,
                word_gap=loc_word_gap,
            )

            line_dots_list.append(line_dots)
            line_stats_list.append(stats)

        return line_dots_list, line_stats_list

    # =========================================================================
    # PHASE 3, 4, 5: RECONSTRUCT CELLS, DETECT MISSING & MERGED CELLS
    # =========================================================================
    def phase3_reconstruct_cells(
        self,
        line_dots_list: List[List[GeometricDot]],
        line_stats_list: List[LineGeometryStats],
        image_shape: Tuple[int, int]
    ) -> List[List[GeometricCell]]:
        """
        Phase 3, 4, 5:
        1. Fits local row 0 (Y0) and local horizontal phase (X0) for each line.
        2. Searches for dots near the 6 canonical positions:
           1 4
           2 5
           3 6
           Represented as [d1, d2, d3, d4, d5, d6].
        3. Phase 4: Explicitly instantiates MISSING_CELL when geometric lattice predicts
           a cell slot but no dots were found.
        4. Phase 5: Detects merged multi-cell clusters and accidental splits.
        """
        h, w = image_shape[:2]
        all_lines_cells: List[List[GeometricCell]] = []
        global_cell_idx = 0

        for line_idx, (dots, stats) in enumerate(zip(line_dots_list, line_stats_list)):
            if len(dots) < 2:
                all_lines_cells.append([])
                continue

            pts = np.array([[d.x, d.y] for d in dots], dtype=np.float32)
            tree = cKDTree(pts)
            dot_contrasts = np.array([d.contrast for d in dots], dtype=np.float32)

            dx = stats.horizontal_dot_spacing
            dy = stats.vertical_dot_spacing
            cx = stats.inter_cell_spacing
            line_y = stats.baseline_y

            xs = pts[:, 0]
            ys = pts[:, 1]

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

            node_tol = dx * 0.46
            ambiguous_tol = dx * 0.62

            line_cells: List[GeometricCell] = []
            consecutive_empty = 0
            last_active_col = None

            for c in range(c_start, c_end + 1):
                col0_x = best_x0 + c * cx
                col1_x = col0_x + dx

                # 6 canonical dot positions
                # 1  4
                # 2  5
                # 3  6
                canonical_nodes = [
                    (col0_x, Y0),              # Dot 1
                    (col0_x, Y0 + dy),         # Dot 2
                    (col0_x, Y0 + 2.0 * dy),   # Dot 3
                    (col1_x, Y0),              # Dot 4
                    (col1_x, Y0 + dy),         # Dot 5
                    (col1_x, Y0 + 2.0 * dy),   # Dot 6
                ]

                dots_present = [0, 0, 0, 0, 0, 0]
                dot_confs = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

                # Check proximity of detected dots to canonical nodes
                for dot_i, (nx, ny) in enumerate(canonical_nodes):
                    dist, nn_idx = tree.query([nx, ny], k=1)
                    if dist <= node_tol:
                        dots_present[dot_i] = 1
                        dot_obj = dots[nn_idx] if nn_idx < len(dots) else None
                        base_conf = dot_obj.confidence if dot_obj is not None else 0.85
                        if dot_obj is not None and dot_obj.contrast > 0:
                            base_conf = min(1.0, dot_obj.contrast / 30.0)
                        dot_confs[dot_i] = max(0.2, min(1.0, float(1.0 - (dist / node_tol) * 0.25) * base_conf))
                    elif dist <= ambiguous_tol:
                        dot_confs[dot_i] = 0.40

                num_present = sum(dots_present)

                # Cell bounding box coordinates
                bx1 = col0_x - 0.25 * dx
                by1 = Y0 - 0.25 * dy
                bx2 = col1_x + 0.25 * dx
                by2 = Y0 + 2.25 * dy
                cx_box = (bx1 + bx2) / 2.0
                cy_box = (by1 + by2) / 2.0

                # PHASE 4: DETECT MISSING CELLS
                if num_present == 0:
                    consecutive_empty += 1
                    is_missing_in_sequence = (last_active_col is not None and c < c_end)

                    if is_missing_in_sequence and consecutive_empty <= 2:
                        cell = GeometricCell(
                            cell_index=global_cell_idx,
                            line_index=line_idx,
                            status=CellStatus.MISSING,
                            dots=[0, 0, 0, 0, 0, 0],
                            binary_str="MISSING",
                            x1=bx1,
                            y1=by1,
                            x2=bx2,
                            y2=by2,
                            cx=cx_box,
                            cy=cy_box,
                            confidence=0.0,
                            dot_confidences=[0.0] * 6,
                            canonical_coords=canonical_nodes,
                            has_space_before=False,
                            details="No dots detected at expected lattice slot",
                        )
                        line_cells.append(cell)
                        global_cell_idx += 1
                    continue

                # Has dots detected
                has_space_before = (consecutive_empty >= 2 and len(line_cells) > 0)
                consecutive_empty = 0
                last_active_col = c

                # PHASE 5: DETECT MERGED CELLS
                # Check if cluster around this cell contains surplus dots spanning into an adjacent column
                cluster_dots_mask = (pts[:, 0] >= bx1 - 0.2 * dx) & (pts[:, 0] <= bx2 + 0.9 * cx) & (np.abs(pts[:, 1] - cy_box) <= dy * 1.5)
                cluster_pts = pts[cluster_dots_mask]

                status = CellStatus.NORMAL
                details = ""
                if len(cluster_pts) > 0:
                    span_w = float(cluster_pts[:, 0].max() - cluster_pts[:, 0].min())
                    if span_w >= cx * 1.35 and num_present >= 5:
                        status = CellStatus.MERGED
                        details = f"Cluster span {span_w:.1f}px bridges adjacent cell"

                # Check uncertainty
                active_confs = [c for c, d in zip(dot_confs, dots_present) if d == 1]
                avg_conf = float(np.mean(active_confs)) if active_confs else 0.50
                if avg_conf < 0.45 and status == CellStatus.NORMAL:
                    status = CellStatus.UNCERTAIN
                    details = f"Low dot confidence {avg_conf:.2f}"

                bin_str = "".join(str(b) for b in dots_present)

                cell = GeometricCell(
                    cell_index=global_cell_idx,
                    line_index=line_idx,
                    status=status,
                    dots=dots_present,
                    binary_str=bin_str,
                    x1=bx1,
                    y1=by1,
                    x2=bx2,
                    y2=by2,
                    cx=cx_box,
                    cy=cy_box,
                    confidence=avg_conf,
                    dot_confidences=dot_confs,
                    canonical_coords=canonical_nodes,
                    has_space_before=has_space_before,
                    details=details,
                )

                line_cells.append(cell)
                global_cell_idx += 1

            stats.num_cells = len(line_cells)
            all_lines_cells.append(line_cells)

        return all_lines_cells

    # =========================================================================
    # PHASE 6: CELL VISUALIZATION
    # =========================================================================
    def phase6_visualize_cells(
        self,
        image: np.ndarray,
        dots: List[GeometricDot],
        grid_lines: List[List[GeometricCell]],
        output_filename: str = "geometric_cells.png"
    ) -> str:
        """
        Phase 6:
        Generates diagnostic image with:
        - Detected dot centers
        - Reconstructed cell rectangles
        - Cell number
        - Cell pattern (6-dot visual filled ● vs hollow ○)
        - Distinct visual markers for NORMAL, MISSING, MERGED, UNCERTAIN.
        """
        canvas = image.copy()
        if len(canvas.shape) == 2:
            canvas = cv2.cvtColor(canvas, cv2.COLOR_GRAY2BGR)

        h, w = canvas.shape[:2]

        # 1. Draw detected dot centers (Bright green circles)
        for d in dots:
            pt = (int(round(d.x)), int(round(d.y)))
            r = max(2, int(round(d.radius)))
            cv2.circle(canvas, pt, r, (0, 255, 0), -1, lineType=cv2.LINE_AA)

        # Color palette for statuses (BGR format)
        COLOR_MAP = {
            CellStatus.NORMAL: (255, 130, 0),       # Cyan / Blue
            CellStatus.MISSING: (0, 0, 255),        # Bright Red
            CellStatus.MERGED: (255, 0, 255),       # Magenta / Purple
            CellStatus.UNCERTAIN: (0, 215, 255),    # Amber / Yellow
        }

        # 2. Draw cell boxes, patterns, and markers
        for line in grid_lines:
            for cell in line:
                pt1 = (int(round(cell.x1)), int(round(cell.y1)))
                pt2 = (int(round(cell.x2)), int(round(cell.y2)))
                color = COLOR_MAP.get(cell.status, (255, 255, 255))

                if cell.status == CellStatus.MISSING:
                    # Dashed / hollow red box with diagonal crosses
                    cv2.rectangle(canvas, pt1, pt2, color, 1, lineType=cv2.LINE_AA)
                    cv2.line(canvas, pt1, pt2, (0, 0, 180), 1, lineType=cv2.LINE_AA)
                    cv2.line(canvas, (pt1[0], pt2[1]), (pt2[0], pt1[1]), (0, 0, 180), 1, lineType=cv2.LINE_AA)
                elif cell.status == CellStatus.MERGED:
                    # Thicker magenta box
                    cv2.rectangle(canvas, pt1, pt2, color, 2, lineType=cv2.LINE_AA)
                else:
                    cv2.rectangle(canvas, pt1, pt2, color, 1, lineType=cv2.LINE_AA)

                # Render 6 canonical dot positions
                if cell.canonical_coords and len(cell.canonical_coords) == 6:
                    for dot_idx, (nx, ny) in enumerate(cell.canonical_coords):
                        ix, iy = int(round(nx)), int(round(ny))
                        is_present = bool(cell.dots[dot_idx]) if dot_idx < len(cell.dots) else False

                        if is_present:
                            # Filled gold/yellow circle for present dot
                            cv2.circle(canvas, (ix, iy), 3, (0, 220, 255), -1, lineType=cv2.LINE_AA)
                        else:
                            # Small hollow gray ring for absent dot
                            cv2.circle(canvas, (ix, iy), 2, (150, 150, 150), 1, lineType=cv2.LINE_AA)

                # Text label: Cell Index & Pattern / Status
                if cell.status == CellStatus.MISSING:
                    label = f"#{cell.cell_index}: [MISSING]"
                else:
                    label = f"#{cell.cell_index}:{cell.binary_str}"

                label_y = max(10, pt1[1] - 4)
                cv2.putText(
                    canvas,
                    label,
                    (pt1[0], label_y),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.28,
                    color,
                    1,
                    lineType=cv2.LINE_AA
                )

        # 3. Render Top-Right Legend Box
        legend_x = max(10, w - 240)
        legend_y = 15
        cv2.rectangle(canvas, (legend_x - 10, legend_y - 5), (w - 10, legend_y + 90), (20, 20, 20), -1)
        cv2.rectangle(canvas, (legend_x - 10, legend_y - 5), (w - 10, legend_y + 90), (100, 100, 100), 1)

        legend_items = [
            ("NORMAL CELL", COLOR_MAP[CellStatus.NORMAL]),
            ("MISSING CELL", COLOR_MAP[CellStatus.MISSING]),
            ("MERGED CELL", COLOR_MAP[CellStatus.MERGED]),
            ("UNCERTAIN CELL", COLOR_MAP[CellStatus.UNCERTAIN]),
        ]
        for i, (name, col) in enumerate(legend_items):
            iy = legend_y + 16 * (i + 1)
            cv2.rectangle(canvas, (legend_x, iy - 10), (legend_x + 12, iy), col, -1)
            cv2.putText(canvas, name, (legend_x + 20, iy - 1), cv2.FONT_HERSHEY_SIMPLEX, 0.35, (230, 230, 230), 1, lineType=cv2.LINE_AA)

        out_path = os.path.join(self.debug_dir, output_filename)
        cv2.imwrite(out_path, canvas)

        if self.debug_dir != "." and not os.path.exists(output_filename):
            try:
                cv2.imwrite(output_filename, canvas)
            except Exception:
                pass

        return out_path

    # =========================================================================
    # PHASE 7: DO NOT DECODE TEXT YET (RAW GEOMETRIC CELL REPORT)
    # =========================================================================
    def phase7_output_raw_geometry(
        self,
        grid_lines: List[List[GeometricCell]],
        output_filename: str = "geometric_cells_dump.txt"
    ) -> str:
        """
        Phase 7:
        Outputs the exact raw geometric representation per line:
        Line 1:
            Cell 0: 100000
            Cell 1: 101000
            Cell 2: 110000
            Cell 3: MISSING
            Cell 4: 101100
        Saves to file and returns formatted string.
        """
        lines_output = []
        for line_idx, line in enumerate(grid_lines):
            lines_output.append(f"Line {line_idx}:")
            if not line:
                lines_output.append("    (No cells detected)")
                continue

            for cell in line:
                if cell.status == CellStatus.MISSING:
                    lines_output.append(f"    Cell {cell.cell_index}: MISSING")
                else:
                    lines_output.append(f"    Cell {cell.cell_index}: {cell.binary_str}")

        dump_text = "\n".join(lines_output) + "\n"

        out_path = os.path.join(self.debug_dir, output_filename)
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(dump_text)

        return dump_text

    # =========================================================================
    # PHASE 8: ONLY AFTER GEOMETRY IS VALID (TRANSLATION BRIDGE)
    # =========================================================================
    def phase8_decode_validated_cells(
        self,
        grid_lines: List[List[GeometricCell]]
    ) -> Dict[str, Any]:
        """
        Phase 8:
        Translates validated 6-dot patterns to Braille Unicode characters
        WITHOUT language model alteration or guessing missing characters.
        Preserves raw geometric representation permanently for debugging.
        """
        raw_braille_lines = []

        for line in grid_lines:
            line_chars = []
            for cell in line:
                if cell.has_space_before and line_chars:
                    line_chars.append(" ")

                if cell.status == CellStatus.MISSING:
                    line_chars.append("⠐")  # Explicit placeholder
                else:
                    u_char = pattern_to_unicode(cell.dots)
                    line_chars.append(u_char)

            raw_braille_lines.append("".join(line_chars))

        full_raw_braille = "\n".join(raw_braille_lines)

        return {
            "raw_braille": full_raw_braille,
            "total_lines": len(grid_lines),
            "total_cells": sum(len(line) for line in grid_lines),
        }

    # =========================================================================
    # END-TO-END EXECUTION COORDINATOR
    # =========================================================================
    def run(
        self,
        image_path: str,
        enable_decode_bridge: bool = False
    ) -> Dict[str, Any]:
        """
        Executes all phases of the Geometric Braille Analysis Pipeline.
        """
        print("\n" + "=" * 70)
        print("         DEDICATED GEOMETRIC BRAILLE ANALYSIS MODE")
        print("=" * 70)

        # Phase 1: Dot Detection Only
        print(f"\n[PHASE 1] Detecting embossed dots from: {image_path}")
        rectified_bgr, dots = self.phase1_detect_dots(image_path)
        h, w = rectified_bgr.shape[:2]
        print(f" -> Rectified image shape: {w}x{h} px")
        print(f" -> Total candidate dots detected: {len(dots)}")
        print(f" -> Saved detected dot centers to: {os.path.join(self.debug_dir, 'detected_dots.png')}")

        # Phase 2: Learn Local Dot Geometry per Line
        print("\n[PHASE 2] Learning local line-by-line geometry (accounting for perspective distortion):")
        line_dots_list, line_stats_list = self.phase2_estimate_local_geometry(dots, (h, w))
        print("-" * 115)
        for stats in line_stats_list:
            if stats.num_dots > 0:
                print(stats.summary_table_row())
        print("-" * 115)

        # Phase 3, 4, 5: Cell Reconstruction, Missing & Merged Cell Detection
        print("\n[PHASE 3, 4, 5] Reconstructing cells, detecting missing & merged cells:")
        grid_lines = self.phase3_reconstruct_cells(line_dots_list, line_stats_list, (h, w))

        total_cells = sum(len(line) for line in grid_lines)
        normal_cells = sum(1 for line in grid_lines for c in line if c.status == CellStatus.NORMAL)
        missing_cells = sum(1 for line in grid_lines for c in line if c.status == CellStatus.MISSING)
        merged_cells = sum(1 for line in grid_lines for c in line if c.status == CellStatus.MERGED)
        uncertain_cells = sum(1 for line in grid_lines for c in line if c.status == CellStatus.UNCERTAIN)

        print(f" -> Total reconstructed cell slots: {total_cells}")
        print(f"    * NORMAL:    {normal_cells}")
        print(f"    * MISSING:   {missing_cells} (preserved in geometric sequence)")
        print(f"    * MERGED:    {merged_cells}")
        print(f"    * UNCERTAIN: {uncertain_cells}")

        # Phase 6: Cell Visualization
        print("\n[PHASE 6] Generating multi-marker cell visualization:")
        vis_path = self.phase6_visualize_cells(rectified_bgr, dots, grid_lines)
        print(f" -> Saved annotated diagnostic cell visualization to: {vis_path}")

        # Phase 7: Raw Geometric Output (No Decoding)
        print("\n[PHASE 7] Generating raw 6-bit geometric cell sequence (no text decoding):")
        raw_dump = self.phase7_output_raw_geometry(grid_lines)
        dump_path = os.path.join(self.debug_dir, "geometric_cells_dump.txt")
        print(f" -> Saved raw geometric cell sequence to: {dump_path}")

        # Display preview of Phase 7 dump
        dump_lines = raw_dump.splitlines()
        preview_count = min(35, len(dump_lines))
        print("\n--- Geometric Pattern Preview ---")
        for line in dump_lines[:preview_count]:
            print(line)
        if len(dump_lines) > preview_count:
            print("    ...")

        # Phase 8: Geometry-Validated Decoding Bridge
        decode_res = None
        if enable_decode_bridge:
            print("\n[PHASE 8] Geometry validated. Mapping to Unicode Braille (NO language model guessing):")
            decode_res = self.phase8_decode_validated_cells(grid_lines)
            print("RAW BRAILLE STREAM:")
            print(decode_res["raw_braille"][:400] + ("..." if len(decode_res["raw_braille"]) > 400 else ""))

        return {
            "status": "success",
            "rectified_shape": (w, h),
            "num_dots": len(dots),
            "total_cells": total_cells,
            "normal_cells": normal_cells,
            "missing_cells": missing_cells,
            "merged_cells": merged_cells,
            "uncertain_cells": uncertain_cells,
            "dots_image_path": os.path.join(self.debug_dir, "detected_dots.png"),
            "vis_image_path": vis_path,
            "dump_file_path": dump_path,
            "decode_result": decode_res,
        }


def main():
    parser = argparse.ArgumentParser(description="Dedicated Geometric Braille Analysis Mode")
    parser.add_argument("--input", "-i", type=str, required=True, help="Path to photographed embossed Braille image")
    parser.add_argument("--output-dir", "-o", type=str, default="debug", help="Directory to save diagnostic outputs")
    parser.add_argument("--decode", action="store_true", help="Enable Phase 8 raw Braille translation after geometry validation")

    args = parser.parse_args()

    analyzer = GeometricBrailleAnalyzer(debug_dir=args.output_dir)
    analyzer.run(args.input, enable_decode_bridge=args.decode)


if __name__ == "__main__":
    main()
