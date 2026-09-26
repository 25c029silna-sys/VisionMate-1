"""
Comprehensive Unit and Integration Test Suite for Braille OCR Pipeline.
Tests:
1. Automatic orientation detection and 180° inversion recovery.
2. Perspective distortion detection and warpPerspective rectification.
3. White-on-white paired luminance extrema dot detection and 2x3 grid fitting.
4. Grade 2 contracted Braille decoding:
   - Word-signs
   - Shortforms
   - Prefix/suffix contractions
   - Number signs and capital signs
   - Beam search ambiguity resolution
5. End-to-end processing on inverted test image.
"""

import os
import sys
import unittest
import numpy as np
import cv2
from PIL import Image

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

from ml.braille_ocr.preprocessor import (
    order_points,
    detect_page_contour,
    warp_perspective,
    analyze_shadow_gradient,
    score_braille_distribution,
    detect_orientation
)
from ml.braille_ocr.dot_segmenter import (
    detect_embossed_dots,
    fit_braille_grid,
    EmbossedDot,
    BrailleGridCell
)
from ml.braille_ocr.grade2_decoder import (
    Grade2BrailleDecoder,
    BeamSearchDecoder
)
from ml.braille_ocr.pipeline import BrailleOCRPipeline


class TestBrailleOCRPipeline(unittest.TestCase):

    def setUp(self):
        self.decoder = Grade2BrailleDecoder()
        self.beam_decoder = BeamSearchDecoder(beam_width=5)

    def test_order_points_and_perspective_warp(self):
        """Validates 4-point ordering and perspective rectification."""
        # Quad corners in randomized order
        pts = np.array([[300, 320], [10, 20], [310, 15], [5, 305]], dtype="float32")
        ordered = order_points(pts)

        # Expected: TL=(10,20), TR=(310,15), BR=(300,320), BL=(5,305)
        self.assertAlmostEqual(ordered[0][0], 10.0, places=1)
        self.assertAlmostEqual(ordered[0][1], 20.0, places=1)
        self.assertAlmostEqual(ordered[1][0], 310.0, places=1)
        self.assertAlmostEqual(ordered[1][1], 15.0, places=1)
        self.assertAlmostEqual(ordered[2][0], 300.0, places=1)
        self.assertAlmostEqual(ordered[2][1], 320.0, places=1)
        self.assertAlmostEqual(ordered[3][0], 5.0, places=1)
        self.assertAlmostEqual(ordered[3][1], 305.0, places=1)

        # Create dummy image and warp
        canvas = np.full((400, 400, 3), 200, dtype=np.uint8)
        warped, M = warp_perspective(canvas, ordered)
        self.assertGreater(warped.shape[0], 250)
        self.assertGreater(warped.shape[1], 250)

    def test_shadow_gradient_dipole_analysis(self):
        """Validates that paired luminance extrema detect highlight-shadow dipoles."""
        # Create synthetic image with bright crests above dark troughs (overhead illumination: dy > 0)
        img = np.full((120, 120), 180, dtype=np.uint8)
        # Dot 1: crest at (40, 40), trough at (40, 45)
        img[39:42, 39:42] = 240  # crest
        img[44:47, 39:42] = 110  # trough
        # Dot 2: crest at (70, 40), trough at (70, 45)
        img[39:42, 69:72] = 240
        img[44:47, 69:72] = 110

        shadow_info = analyze_shadow_gradient(img, kernel_size=7)
        self.assertTrue(shadow_info['shadow_below'], "Expected shadow below crest for overhead illumination")
        self.assertGreater(shadow_info['mean_dy'], 0.0)

    def test_braille_frequency_scoring_inversion(self):
        """Validates that normal Braille scores high and 180° inverted cells score low/negative."""
        # Standard letters: 'a', 'b', 'c', 'd', 'e', 'l', 'm', 'n', 'the', 'and', 'for'
        # Classes: 32 (a), 48 (b), 36 (c), 38 (d), 34 (e), 56 (l), 44 (m), 46 (n), 29 (the), 61 (and), 59 (for)
        normal_cells = [32, 48, 36, 38, 34, 56, 44, 46, 29, 61, 59, 32, 48, 36, 38]
        normal_score = score_braille_distribution(normal_cells)

        # 180° Inverted cells (upper dots inverted to lower dots -> punctuation like comma, semicolon, quotes, hyphen)
        # Classes: 1 (comma), 3 (semicolon), 8 (apostrophe), 9 (hyphen), 11 (period), 18 (colon), 24 (semicolon)
        inverted_cells = [1, 3, 8, 9, 11, 18, 24, 1, 3, 8, 9, 11, 18, 24, 1]
        inverted_score = score_braille_distribution(inverted_cells)

        self.assertGreater(normal_score, 0.0, "Normal Braille should have a positive score")
        self.assertLess(inverted_score, 0.0, "Inverted punctuation-heavy cells should have a negative score")
        self.assertGreater(normal_score, inverted_score + 40.0, "Normal score should significantly exceed inverted score")

    def test_grade2_wordsigns_and_shortforms(self):
        """Tests expansion of Grade 2 Braille alphabetic word-signs and shortforms."""
        # 'b' standing alone -> 'but'
        # 'c' standing alone -> 'can'
        # 'p' standing alone -> 'people'
        # 'x' standing alone -> 'it'
        stream = [
            ('110000', False), # b
            ('100000', True),  # space + a (a stays a)
            ('100100', True),  # space + c (can)
            ('111100', True),  # space + p (people)
            ('101101', True),  # space + x (it)
        ]
        text = self.decoder.decode_cells_linear(stream)
        self.assertEqual(text, "but a can people it")

        # Shortforms: 'cd' -> 'could', 'wd' -> 'would', 'fr' -> 'friend', 'ab' -> 'about'
        cd_stream = [
            ('100100', False), # c
            ('100110', False), # d
            ('100000', True),  # space + a
            ('110100', True),  # space + f
            ('111010', False), # r -> fr -> friend
        ]
        cd_text = self.decoder.decode_cells_linear(cd_stream)
        self.assertEqual(cd_text, "could a friend")

    def test_grade2_contractions_and_numbers(self):
        """Tests prefix/suffix group contractions and numeric mode."""
        # Contractions: 'the' (011101), 'and' (111101), 'for' (111111), 'with' (011111)
        group_stream = [
            ('011101', False), # the
            ('111101', True),  # and
            ('111111', True),  # for
            ('011111', True),  # with
        ]
        text = self.decoder.decode_cells_linear(group_stream)
        self.assertEqual(text, "the and for with")

        # Numbers: '#ab' -> '12', '#cj' -> '30', '#aiai' -> '1719'
        num_stream = [
            ('001111', False), # #
            ('100000', False), # a -> 1
            ('110000', False), # b -> 2
            ('100000', True),  # space + a -> 'a' (numeric mode ends after space)
        ]
        num_text = self.decoder.decode_cells_linear(num_stream)
        self.assertEqual(num_text, "12 a")

        # Capital indicator: ',' (000001) followed by 'b' -> 'But'
        cap_stream = [
            ('000001', False), # capital indicator
            ('110000', False), # b -> But
        ]
        cap_text = self.decoder.decode_cells_linear(cap_stream)
        self.assertEqual(cap_text, "But")

    def test_beam_search_disambiguation(self):
        """Tests that beam search resolves ambiguous tokens using English lexicon."""
        # Suppose cells represent 'c' 'd' (could) followed by 'fr' (friends)
        cells_line = [
            BrailleGridCell(0, 0, 10, 10, 5, 5, [1,0,0,1,0,0], '100100', 36, False), # c
            BrailleGridCell(12, 0, 22, 10, 17, 5, [1,0,0,1,1,0], '100110', 38, False), # d
            BrailleGridCell(40, 0, 50, 10, 45, 5, [1,1,0,1,0,0], '110100', 52, True), # space + f
            BrailleGridCell(52, 0, 62, 10, 57, 5, [1,1,1,0,1,0], '111010', 58, False), # r
        ]
        decoded = self.beam_decoder.decode([[cells_line[0], cells_line[1]], [cells_line[2], cells_line[3]]])
        self.assertIn("could", decoded.lower())
        self.assertIn("friend", decoded.lower())

    def test_dot_detection_and_grid_fitting_synthetic(self):
        """Tests geometric embossed dot detection and 2x3 grid fitting on synthetic pattern."""
        h, w = 150, 250
        synth_img = np.full((h, w), 200, dtype=np.uint8)

        # Draw a 2x3 cell with dots 1, 2, 4 (letter 'f')
        # Dot spacing dx=14, dy=14
        ox, oy = 50, 40
        coords = [
            (ox, oy),          # Dot 1: col 0, row 0
            (ox, oy + 14),     # Dot 2: col 0, row 1
            (ox + 14, oy),     # Dot 4: col 1, row 0
        ]
        for cx, cy in coords:
            synth_img[cy-2:cy+1, cx-2:cx+1] = 250  # crest
            synth_img[cy+2:cy+5, cx-2:cx+1] = 90   # trough below

        dots = detect_embossed_dots(synth_img, min_radius=1.5, max_radius=8.0, min_contrast=8.0)
        self.assertGreaterEqual(len(dots), 3)

        grid_lines = fit_braille_grid(dots, synth_img.shape, expected_dot_pitch=14.0)
        self.assertGreaterEqual(len(grid_lines), 1)
        first_cell = grid_lines[0][0]
        # Dots 1, 2, 4 active => [1, 1, 0, 1, 0, 0]
        self.assertEqual(first_cell.dots[0], 1)
        self.assertEqual(first_cell.dots[1], 1)
        self.assertEqual(first_cell.dots[3], 1)

    def test_pipeline_on_inverted_sample(self):
        """Tests that pipeline takes a 180° inverted test image, auto-rotates by 180°, and decodes."""
        test_img_path = "ml/yolov8_braille/captured_phone.jpg"
        if not os.path.exists(test_img_path):
            self.skipTest("captured_phone.jpg not found")

        # Load and intentionally invert by 180°
        orig = Image.open(test_img_path)
        from PIL import ImageOps
        baked = ImageOps.exif_transpose(orig)
        inverted_180 = baked.rotate(180, expand=True)

        inv_bgr = cv2.cvtColor(np.array(inverted_180.convert('RGB')), cv2.COLOR_RGB2BGR)

        pipeline = BrailleOCRPipeline(tflite_model_path="app/assets/models/yolov8_braille.tflite")
        result = pipeline.process_image(inv_bgr)

        # Pipeline should identify that 180° rotation is required
        applied_rot = result['orientation_applied']
        self.assertEqual(applied_rot, 180, f"Expected 180° rotation to correct upside-down image, got {applied_rot}°")

        # Text should not be garbled semicolons
        text = result['text']
        self.assertGreater(len(text), 10, "Decoded text should not be empty")

        # Inverted garbled output had semicolons like '; a ed( ; ;'
        # With 180° auto-correction, semicolon ratio should be low (< 10%)
        semicolon_count = text.count(';')
        total_chars = max(1, len(text))
        self.assertLess(semicolon_count / total_chars, 0.10, "Text should not be dominated by semicolons")
        print(f"\n[PASS] Pipeline correctly auto-rotated 180° inverted image! Output sample:\n{text[:200]}")


    def test_shipwrecked_sailor_recovery_and_dictionary_pass(self):
        """
        Validates the 4 final recovery layer enhancements:
        1. Widen inter-cell whitespace threshold (> 1.6x cx).
        2. Lower Dot 6 detection threshold for word boundaries ('watq' -> 'water', 'locoq' -> 'locker').
        3. Dictionary / Lexicon post-correction pass ('watq' -> 'water', 'moutes' -> 'minutes',
           'pree busis' -> 'precious', 'cdrel' -> 'could rely', 'm s l it u de' -> 'my solitude').
        4. Polished English narrative text with line breaks preserved.
        """
        from ml.braille_ocr.language_model import BrailleLanguageModel
        lm = BrailleLanguageModel()

        raw_ocr_input = (
            "THE STORY OF A SHIPWRECKED SAILOR\n"
            "By Gabriel Garcia Marquez\n\n"
            "I was alone in the sea without food or salt watq.\n"
            "pwii moutes later, another sailor disappeared.\n"
            "m s l it u de in the ocean was vast, s I cdrel on nobody.\n"
            "In m pockets were twenty pesos, and kes to m loco q in pbili.\n"
            "pree busis belongings were safe until i was res cu."
        )

        polished_text = lm.refine(raw_ocr_input)
        lines = polished_text.splitlines()

        # Assert key phrases and line breaks are accurately resolved
        self.assertIn("salt water", polished_text)
        self.assertIn("three minutes", polished_text)
        self.assertIn("another sailor", polished_text)
        self.assertIn("my solitude", polished_text)
        self.assertIn("could rely", polished_text)
        self.assertIn("twenty pesos", polished_text)
        self.assertIn("keys to my locker in Mobile", polished_text)
        self.assertIn("precious", polished_text)
        self.assertIn("until I was rescued", polished_text)

        # Assert line breaks are preserved
        self.assertGreaterEqual(len(lines), 5)


if __name__ == '__main__':
    unittest.main()
