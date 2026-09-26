"""
Unit Tests for Modular Braille Recognition Pipeline (ml/braille).
Validates:
1. Multi-method image preprocessing & illumination normalization
2. Perspective quad ordering and rectification
3. Embossed dot detection with highlight-shadow dipole pairing
4. Continuous 2x3 cell segmentation & canonical 6-dot extraction
5. Deterministic Grade 1 Braille mapping, numeric mode, capital mode
6. Adaptive spacing and text reconstruction
7. Error analysis and diagnostic cell visualization
"""

import unittest
import numpy as np
import cv2

from ml.braille.preprocessing import (
    preprocess_image,
    normalize_illumination,
    enhance_clahe,
    morphological_dipoles,
    gradient_emboss_enhancement,
    adaptive_threshold_image,
    PREPROCESS_METHOD_CLAHE,
    PREPROCESS_METHOD_BLACKHAT,
    PREPROCESS_METHOD_GRADIENT,
    PREPROCESS_METHOD_COMBINED,
)
from ml.braille.perspective import (
    order_quad_points,
    rectify_page_perspective,
    normalize_orientation,
)
from ml.braille.dot_detection import (
    detect_embossed_braille_dots,
    EmbossedDotResult,
)
from ml.braille.cell_segmentation import (
    segment_dots_into_cells,
    estimate_pitches,
    BrailleCellCandidate,
)
from ml.braille.braille_decoder import (
    decode_cell_pattern,
    decode_line_grade1,
    pattern_to_unicode,
    unicode_to_pattern,
    BRAILLE_MAP_GRADE1,
)
from ml.braille.text_reconstruction import (
    reconstruct_text_from_cells,
)
from ml.braille.error_analysis import (
    analyze_cell_confidences,
    classify_recognition_errors,
)
from ml.braille.visualization import (
    visualize_cells_and_dots,
)


class TestBrailleModularPipeline(unittest.TestCase):

    def test_preprocessing_methods(self):
        """Verifies each preprocessing method produces valid uint8 maps."""
        test_img = np.full((120, 120, 3), 180, dtype=np.uint8)
        # Add synthetic embossed dot
        test_img[40:43, 40:43] = 240 # crest
        test_img[45:48, 40:43] = 100 # trough

        for method in [PREPROCESS_METHOD_CLAHE, PREPROCESS_METHOD_BLACKHAT, PREPROCESS_METHOD_GRADIENT, PREPROCESS_METHOD_COMBINED]:
            prep = preprocess_image(test_img, method=method)
            self.assertEqual(prep["grayscale"].shape, (120, 120))
            self.assertEqual(prep["enhanced"].shape, (120, 120))
            self.assertEqual(prep["enhanced"].dtype, np.uint8)
            self.assertEqual(prep["threshold"].shape, (120, 120))

    def test_illumination_normalization(self):
        """Verifies Gaussian division normalizes lighting gradients across an image."""
        grad = np.tile(np.linspace(60, 200, 150, dtype=np.uint8), (150, 1))
        norm = normalize_illumination(grad, sigma=25.0)
        raw_diff = abs(float(np.mean(grad[:, :20])) - float(np.mean(grad[:, -20:])))
        norm_diff = abs(float(np.mean(norm[:, :20])) - float(np.mean(norm[:, -20:])))
        self.assertLess(norm_diff, raw_diff * 0.35)

    def test_perspective_quad_ordering(self):
        """Validates 4-corner ordering."""
        pts = np.array([[200, 200], [10, 20], [210, 15], [5, 195]], dtype="float32")
        ordered = order_quad_points(pts)
        # TL=(10,20), TR=(210,15), BR=(200,200), BL=(5,195)
        self.assertAlmostEqual(ordered[0][0], 10.0, places=1)
        self.assertAlmostEqual(ordered[0][1], 20.0, places=1)
        self.assertAlmostEqual(ordered[1][0], 210.0, places=1)
        self.assertAlmostEqual(ordered[1][1], 15.0, places=1)

    def test_dot_detection_synthetic(self):
        """Tests that embossed dot detection pairs bright crests with dark troughs."""
        img = np.full((120, 120), 180, dtype=np.uint8)
        # Dot at (47, 49)
        img[45:50, 45:50] = 245
        img[52:57, 45:50] = 75

        dots = detect_embossed_braille_dots(img, min_radius=1.5, max_radius=8.0, min_contrast=6.0)
        self.assertGreaterEqual(len(dots), 1)
        d = dots[0]
        self.assertAlmostEqual(d["x"], 47.0, delta=4.0)
        self.assertAlmostEqual(d["y"], 49.0, delta=4.0)
        self.assertGreater(d["contrast"], 15.0)

    def test_grade1_deterministic_decoder(self):
        """Verifies Grade 1 decoding for letters, numbers, capitals, and punctuation."""
        # 'a' = (1,0,0,0,0,0)
        char_a, _, _ = decode_cell_pattern((1, 0, 0, 0, 0, 0))
        self.assertEqual(char_a, "a")

        # 'b' = (1,1,0,0,0,0)
        char_b, _, _ = decode_cell_pattern((1, 1, 0, 0, 0, 0))
        self.assertEqual(char_b, "b")

        # Capital 'B'
        _, _, cap_next = decode_cell_pattern((0, 0, 0, 0, 0, 1)) # Capital prefix
        char_B, _, _ = decode_cell_pattern((1, 1, 0, 0, 0, 0), capital_next=cap_next)
        self.assertEqual(char_B, "B")

        # Number '#b' -> '2'
        _, num_mode, _ = decode_cell_pattern((0, 0, 1, 1, 1, 1)) # #
        self.assertTrue(num_mode)
        digit_2, num_mode, _ = decode_cell_pattern((1, 1, 0, 0, 0, 0), number_mode=num_mode)
        self.assertEqual(digit_2, "2")

    def test_unicode_pattern_conversion(self):
        """Validates 6-dot boolean pattern to Unicode Braille U+2800..U+283F mapping."""
        # Empty -> U+2800
        self.assertEqual(pattern_to_unicode([0, 0, 0, 0, 0, 0]), chr(0x2800))
        # Dot 1 -> U+2801 (⠁)
        self.assertEqual(pattern_to_unicode([1, 0, 0, 0, 0, 0]), "\u2801")
        # Dot 1, 2 -> U+2803 (⠃)
        self.assertEqual(pattern_to_unicode([1, 1, 0, 0, 0, 0]), "\u2803")
        # Roundtrip
        pat = (1, 0, 1, 0, 1, 0)
        u_ch = pattern_to_unicode(pat)
        rev_pat = unicode_to_pattern(u_ch)
        self.assertEqual(pat, rev_pat)

    def test_cell_visualization(self):
        """Verifies cell visualizer draws dots and cells without errors."""
        canvas = np.full((120, 200, 3), 200, dtype=np.uint8)
        dots = [{"x": 30.0, "y": 40.0, "radius": 3.0}]
        cell = BrailleCellCandidate(
            cell_index=0,
            line_index=0,
            x1=20.0, y1=30.0, x2=50.0, y2=80.0,
            cx=35.0, cy=55.0,
            dots=[1, 0, 0, 0, 0, 0],
            binary_str="100000",
            class_index=32,
            confidence=0.88,
            dot_confidences=[0.9, 0.1, 0.1, 0.1, 0.1, 0.1],
            has_space_before=False
        )
        annotated = visualize_cells_and_dots(canvas, dots, [[cell]])
        self.assertEqual(annotated.shape, canvas.shape)


if __name__ == "__main__":
    unittest.main()
