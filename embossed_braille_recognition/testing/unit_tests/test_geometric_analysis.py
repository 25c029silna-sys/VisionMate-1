"""
Unit and Integration Test Suite for Dedicated Geometric Braille Analysis Mode.
Tests:
1. Phase 1: Dot detection & saving image of ONLY detected dot centers.
2. Phase 2: Independent local line geometry estimation (no global assumption).
3. Phase 3: Canonical 6-dot cell reconstruction ([d1, d2, d3, d4, d5, d6]).
4. Phase 4: Explicit MISSING_CELL generation in sequence (no index collapse).
5. Phase 5: Merged and split cell detection.
6. Phase 6: Diagnostic multi-marker cell visualization generation.
7. Phase 7: Raw geometric cell dump formatting without text decoding.
8. Phase 8: Deterministic decoding bridge without LLM hallucination.
"""

import os
import sys
import unittest
import numpy as np
import cv2

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

from ml.braille.geometric_analysis import (
    GeometricBrailleAnalyzer,
    GeometricDot,
    GeometricCell,
    CellStatus,
    LineGeometryStats,
)


class TestGeometricBrailleAnalysis(unittest.TestCase):

    def setUp(self):
        self.debug_dir = os.path.join("debug", "test_geometric")
        os.makedirs(self.debug_dir, exist_ok=True)
        self.analyzer = GeometricBrailleAnalyzer(debug_dir=self.debug_dir)

    def test_phase1_dot_canvas_creation(self):
        """Verifies Phase 1 creates a canvas containing only detected dot centers."""
        # Create synthetic image with 3 embossed dots
        synthetic = np.full((120, 200, 3), 220, dtype=np.uint8)
        # Highlight/shadow dipoles
        # Dot 1 at (40, 50)
        cv2.circle(synthetic, (39, 49), 4, (255, 255, 255), -1)
        cv2.circle(synthetic, (42, 52), 4, (120, 120, 120), -1)
        # Dot 2 at (40, 70)
        cv2.circle(synthetic, (39, 69), 4, (255, 255, 255), -1)
        cv2.circle(synthetic, (42, 72), 4, (120, 120, 120), -1)

        test_img_path = os.path.join(self.debug_dir, "synth_input.png")
        cv2.imwrite(test_img_path, synthetic)

        rectified, dots = self.analyzer.phase1_detect_dots(test_img_path, output_filename="test_dots.png")
        dots_path = os.path.join(self.debug_dir, "test_dots.png")

        self.assertTrue(os.path.exists(dots_path), "detected_dots.png artifact must be created")
        dot_img = cv2.imread(dots_path)
        self.assertEqual(dot_img.shape[:2], rectified.shape[:2], "Dots canvas must match rectified image dimensions")

    def test_phase2_independent_line_geometry_estimation(self):
        """Verifies that each line receives independent pitch estimates without a global value."""
        # Line 0: tight pitch dy=12, dx=12, cx=32
        line0_dots = [
            GeometricDot(x=20.0, y=30.0, radius=3.0, confidence=0.9),
            GeometricDot(x=20.0, y=42.0, radius=3.0, confidence=0.9),
            GeometricDot(x=32.0, y=30.0, radius=3.0, confidence=0.9),
            GeometricDot(x=52.0, y=30.0, radius=3.0, confidence=0.9),
            GeometricDot(x=52.0, y=42.0, radius=3.0, confidence=0.9),
            GeometricDot(x=64.0, y=30.0, radius=3.0, confidence=0.9),
        ]
        # Line 1: wider pitch dy=18, dx=18, cx=50 (e.g. perspective distortion closer to camera)
        line1_dots = [
            GeometricDot(x=20.0, y=120.0, radius=4.0, confidence=0.9),
            GeometricDot(x=20.0, y=138.0, radius=4.0, confidence=0.9),
            GeometricDot(x=38.0, y=120.0, radius=4.0, confidence=0.9),
            GeometricDot(x=70.0, y=120.0, radius=4.0, confidence=0.9),
            GeometricDot(x=70.0, y=138.0, radius=4.0, confidence=0.9),
            GeometricDot(x=88.0, y=120.0, radius=4.0, confidence=0.9),
        ]
        all_dots = line0_dots + line1_dots

        line_dots, line_stats = self.analyzer.phase2_estimate_local_geometry(all_dots, (200, 200))
        self.assertEqual(len(line_stats), 2, "Must detect exactly 2 lines")

        # Line 0 must estimate smaller pitch than Line 1
        stat0, stat1 = line_stats[0], line_stats[1]
        self.assertLess(stat0.vertical_dot_spacing, stat1.vertical_dot_spacing,
                        "Line 0 dy should be smaller than Line 1 dy reflecting local perspective")
        self.assertLess(stat0.inter_cell_spacing, stat1.inter_cell_spacing,
                        "Line 0 cx should be smaller than Line 1 cx reflecting local perspective")

    def test_phase4_missing_cell_retention_in_sequence(self):
        """Verifies that an unembossed/empty cell slot is explicitly created as MISSING_CELL."""
        dx, dy, cx = 14.0, 14.0, 40.0
        X0, Y0 = 30.0, 50.0

        # Synthetic Line:
        # Cell 0 (c=0): Dot 1 (X0, Y0) and Dot 2 (X0, Y0+dy) -> 'b'
        # Cell 1 (c=1): MISSING (0 dots detected at X0+cx)
        # Cell 2 (c=2): Dot 1 (X0+2*cx, Y0) and Dot 4 (X0+2*cx+dx, Y0) -> 'c'
        test_dots = [
            GeometricDot(x=X0, y=Y0, radius=3.0, confidence=0.95),
            GeometricDot(x=X0, y=Y0 + dy, radius=3.0, confidence=0.95),
            GeometricDot(x=X0 + 2.0 * cx, y=Y0, radius=3.0, confidence=0.95),
            GeometricDot(x=X0 + 2.0 * cx + dx, y=Y0, radius=3.0, confidence=0.95),
        ]

        stats = LineGeometryStats(
            line_index=0,
            baseline_y=Y0 + dy,
            num_dots=len(test_dots),
            num_cells=0,
            vertical_dot_spacing=dy,
            horizontal_dot_spacing=dx,
            intra_cell_col_spacing=dx,
            inter_cell_spacing=cx,
            inter_cell_gap=cx - dx,
            word_spacing=2.0 * cx,
            word_gap=2.0 * cx - dx,
        )

        grid_lines = self.analyzer.phase3_reconstruct_cells([[d for d in test_dots]], [stats], (150, 300))
        self.assertEqual(len(grid_lines), 1)
        cells = grid_lines[0]

        # Must have 3 cells: Cell 0 (active), Cell 1 (MISSING), Cell 2 (active)
        self.assertEqual(len(cells), 3, "Missing cell MUST NOT be skipped; sequence must have 3 cells")
        self.assertEqual(cells[0].status, CellStatus.NORMAL)
        self.assertEqual(cells[0].dots, [1, 1, 0, 0, 0, 0])
        self.assertEqual(cells[0].binary_str, "110000")

        self.assertEqual(cells[1].status, CellStatus.MISSING, "Cell 1 must be flagged as MISSING")
        self.assertEqual(cells[1].binary_str, "MISSING")
        self.assertEqual(cells[1].dots, [0, 0, 0, 0, 0, 0])

        self.assertEqual(cells[2].status, CellStatus.NORMAL)
        self.assertEqual(cells[2].dots, [1, 0, 0, 1, 0, 0])
        self.assertEqual(cells[2].binary_str, "100100")

    def test_phase7_raw_geometric_dump_format(self):
        """Verifies Phase 7 outputs raw geometric sequence without character decoding."""
        cell0 = GeometricCell(
            cell_index=0, line_index=0, status=CellStatus.NORMAL,
            dots=[1, 0, 0, 0, 0, 0], binary_str="100000",
            x1=10, y1=10, x2=25, y2=45, cx=17, cy=27, confidence=0.9
        )
        cell1 = GeometricCell(
            cell_index=1, line_index=0, status=CellStatus.MISSING,
            dots=[0, 0, 0, 0, 0, 0], binary_str="MISSING",
            x1=40, y1=10, x2=55, y2=45, cx=47, cy=27, confidence=0.0
        )
        cell2 = GeometricCell(
            cell_index=2, line_index=0, status=CellStatus.NORMAL,
            dots=[1, 0, 1, 0, 0, 0], binary_str="101000",
            x1=70, y1=10, x2=85, y2=45, cx=77, cy=27, confidence=0.92
        )

        dump = self.analyzer.phase7_output_raw_geometry([[cell0, cell1, cell2]], output_filename="test_dump.txt")
        self.assertIn("Line 0:", dump)
        self.assertIn("Cell 0: 100000", dump)
        self.assertIn("Cell 1: MISSING", dump)
        self.assertIn("Cell 2: 101000", dump)

    def test_phase8_deterministic_decoding_bridge(self):
        """Verifies Phase 8 produces deterministic Unicode Braille without language model hallucination."""
        # Cell 'a': [1,0,0,0,0,0] -> ⠁
        # Cell 'b': [1,1,0,0,0,0] -> ⠃
        cell_a = GeometricCell(
            cell_index=0, line_index=0, status=CellStatus.NORMAL,
            dots=[1, 0, 0, 0, 0, 0], binary_str="100000",
            x1=10, y1=10, x2=25, y2=45, cx=17, cy=27
        )
        cell_b = GeometricCell(
            cell_index=1, line_index=0, status=CellStatus.NORMAL,
            dots=[1, 1, 0, 0, 0, 0], binary_str="110000",
            x1=40, y1=10, x2=55, y2=45, cx=47, cy=27
        )

        res = self.analyzer.phase8_decode_validated_cells([[cell_a, cell_b]])
        self.assertEqual(res["raw_braille"], "⠁⠃")


if __name__ == "__main__":
    unittest.main()
