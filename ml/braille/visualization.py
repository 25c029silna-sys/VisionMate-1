"""
Braille Cell and Dot Visualization Module.
Renders diagnostic overlays to visually verify:
- Detected dot centroids
- Cell bounding boxes
- Canonical 6-dot positions (filled circle = dot present, hollow circle = dot absent)
- Cell index, decoded character/symbol, and confidence score
Enables immediate visual determination of whether errors stem from dot detection or cell segmentation.
"""

import os
import cv2
import numpy as np
from typing import List, Dict, Any, Optional
from .cell_segmentation import BrailleCellCandidate


def visualize_cells_and_dots(
    image: np.ndarray,
    dots: List[Dict[str, Any]],
    grid_lines: List[List[BrailleCellCandidate]],
    output_path: Optional[str] = None
) -> np.ndarray:
    """
    Renders diagnostic visualization:
    - Green circles for all detected dot centroids (radius proportional to detection).
    - Blue rectangles for each 2x3 cell bounding box.
    - Six canonical dot positions:
        * Filled yellow/orange circle for PRESENT dot (1).
        * Small hollow gray ring for ABSENT dot (0).
    - Text annotation above each cell: Cell index, 6-bit pattern, and confidence.

    Saves annotated image to output_path if provided, and returns annotated canvas.
    """
    canvas = image.copy()
    if len(canvas.shape) == 2:
        canvas = cv2.cvtColor(canvas, cv2.COLOR_GRAY2BGR)

    h, w = canvas.shape[:2]

    # 1. Draw detected dot centroids (Bright green filled circles)
    for d in dots:
        dx = int(round(d.get("x", 0)))
        dy = int(round(d.get("y", 0)))
        dr = max(2, int(round(d.get("radius", 3.0))))
        cv2.circle(canvas, (dx, dy), dr, (0, 255, 0), -1, lineType=cv2.LINE_AA)

    # 2. Draw cell bounding boxes and 6 canonical dot positions
    for line in grid_lines:
        for cell in line:
            pt1 = (int(round(cell.x1)), int(round(cell.y1)))
            pt2 = (int(round(cell.x2)), int(round(cell.y2)))

            # Cell boundary: Cyan/Blue rectangle
            cv2.rectangle(canvas, pt1, pt2, (255, 120, 0), 1, lineType=cv2.LINE_AA)

            # Draw 6 canonical dot positions
            # Dots 1..6:
            # Col 0: Dot 1 (top), Dot 2 (mid), Dot 3 (bottom)
            # Col 1: Dot 4 (top), Dot 5 (mid), Dot 6 (bottom)
            if cell.canonical_coords and len(cell.canonical_coords) == 6:
                coords = cell.canonical_coords
            else:
                cw = cell.x2 - cell.x1
                ch = cell.y2 - cell.y1
                c0_x = cell.x1 + 0.25 * cw
                c1_x = cell.x2 - 0.25 * cw
                r0_y = cell.y1 + 0.18 * ch
                r1_y = cell.y1 + 0.50 * ch
                r2_y = cell.y1 + 0.82 * ch
                coords = [
                    (c0_x, r0_y), (c0_x, r1_y), (c0_x, r2_y),
                    (c1_x, r0_y), (c1_x, r1_y), (c1_x, r2_y)
                ]

            for dot_idx, (cx_pt, cy_pt) in enumerate(coords):
                ix = int(round(cx_pt))
                iy = int(round(cy_pt))
                is_present = bool(cell.dots[dot_idx]) if dot_idx < len(cell.dots) else False

                if is_present:
                    # Filled yellow/gold circle for present dot
                    cv2.circle(canvas, (ix, iy), 3, (0, 220, 255), -1, lineType=cv2.LINE_AA)
                else:
                    # Hollow gray circle for absent dot position
                    cv2.circle(canvas, (ix, iy), 2, (160, 160, 160), 1, lineType=cv2.LINE_AA)

            # Cell label: Index and binary pattern
            label = f"#{cell.cell_index}:{cell.binary_str}"
            label_y = max(10, pt1[1] - 4)
            cv2.putText(
                canvas,
                label,
                (pt1[0], label_y),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.28,
                (255, 255, 255),
                1,
                lineType=cv2.LINE_AA
            )

    if output_path:
        out_dir = os.path.dirname(os.path.abspath(output_path))
        if out_dir and not os.path.exists(out_dir):
            os.makedirs(out_dir, exist_ok=True)
        cv2.imwrite(output_path, canvas)

    return canvas


def export_cell_diagnostics(
    image: np.ndarray,
    dots: List[Dict[str, Any]],
    grid_lines: List[List[BrailleCellCandidate]],
    filename_stem: str,
    output_dir: str = "debug"
) -> str:
    """
    Standard helper saving to debug/cells_<filename>.png as required.
    """
    if not os.path.exists(output_dir):
        os.makedirs(output_dir, exist_ok=True)
    out_path = os.path.join(output_dir, f"cells_{filename_stem}.png")
    visualize_cells_and_dots(image, dots, grid_lines, output_path=out_path)
    return out_path
