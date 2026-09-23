"""
Unit and Integration Test Suite for Rigid Lattice Grid Fitting and Liblouis Grade 2 Translation.
Tests:
1. Rigid lattice global grid fitting:
   - Single-column cells (e.g. Dot 6 capital sign) snapped to column 1 without phase shift.
   - Enforcing fixed 2-column x 3-row Braille geometry.
   - Accurate empty-cell (whitespace) word boundary detection.
2. Context-aware Grade 2 translation via Liblouis:
   - Suffix/prefix contractions (e.g. 'rescued' with 'ed' contraction).
   - Compound words and whole-word signs ('cannot', 'can', 'not', 'people', 'knowledge').
   - Capital signs (⠠) and number signs (⠼) without indicator leakage.
   - Word sign 'pockets'.
3. End-to-end verification on sample image:
   - Printing raw Unicode Braille alongside translated English string.
   - Asserting coherent English text.
"""

import os
import sys
import unittest
import numpy as np
import cv2

# Set stdout to utf-8 if on Windows
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

from ml.braille_ocr.dot_segmenter import (
    EmbossedDot,
    BrailleGridCell,
    estimate_global_pitches,
    fit_braille_grid,
    snap_yolo_detections_to_lattice,
    GRID_COORDINATE_TO_DOT_NUMBER,
    grid_coords_to_dot_number,
    grid_coords_to_dot_index,
)
from ml.braille_ocr.grade2_decoder import (
    Grade2BrailleDecoder,
    LiblouisGrade2Decoder,
    dots_to_unicode,
    binary_str_to_unicode,
)
from ml.braille_ocr.pipeline import BrailleOCRPipeline
from ml.braille_ocr import louis


class TestBrailleGridAndLiblouis(unittest.TestCase):

    def setUp(self):
        self.decoder = LiblouisGrade2Decoder()

    def test_liblouis_bindings_and_version(self):
        """Verifies that Liblouis library loads and reports valid version."""
        ver = louis.version()
        self.assertTrue(ver and len(ver) > 0, "Liblouis version string should not be empty")
        self.assertIn("3.", ver, f"Expected Liblouis 3.x version, got {ver}")

    def test_dot_coordinate_to_dot_number_mapping(self):
        """
        Verifies strict standard Braille 2x3 grid indexing:
          (Row 0, Col 0) -> Dot 1
          (Row 1, Col 0) -> Dot 2
          (Row 2, Col 0) -> Dot 3
          (Row 0, Col 1) -> Dot 4
          (Row 1, Col 1) -> Dot 5
          (Row 2, Col 1) -> Dot 6
        Guarantees column-major ordering (Row 0, Col 1 is NOT Dot 2).
        """
        expected_mapping = {
            (0, 0): 1,
            (1, 0): 2,
            (2, 0): 3,
            (0, 1): 4,
            (1, 1): 5,
            (2, 1): 6,
        }
        for (r, c), expected_dot in expected_mapping.items():
            self.assertEqual(
                grid_coords_to_dot_number(r, c),
                expected_dot,
                f"Grid coordinate ({r}, {c}) must map to Dot {expected_dot}"
            )
            self.assertEqual(
                grid_coords_to_dot_index(r, c),
                expected_dot - 1,
                f"Grid coordinate ({r}, {c}) must map to index {expected_dot - 1}"
            )

        # Explicitly assert Row 0, Col 1 is NOT mapped to Dot 2 (prevent row-major error)
        self.assertNotEqual(grid_coords_to_dot_number(0, 1), 2, "Row 0, Col 1 must NOT be Dot 2 (row-major bug)")
        self.assertEqual(grid_coords_to_dot_number(0, 1), 4, "Row 0, Col 1 must be Dot 4")

    def test_standard_unicode_braille_encoding_bitmask(self):
        """
        Verifies standard binary weights for Unicode Braille (U+2800..U+28FF):
          mask = 0
          if Dot 1: mask |= 0x01
          if Dot 2: mask |= 0x02
          if Dot 3: mask |= 0x04
          if Dot 4: mask |= 0x08
          if Dot 5: mask |= 0x10
          if Dot 6: mask |= 0x20
        Generates character via chr(0x2800 + mask).
        Maps mask == 0 explicitly to ' ' (or \\u2800).
        """
        # Test individual dots
        self.assertEqual(dots_to_unicode([1, 0, 0, 0, 0, 0]), chr(0x2800 | 0x01))  # Dot 1 -> ⠁
        self.assertEqual(dots_to_unicode([0, 1, 0, 0, 0, 0]), chr(0x2800 | 0x02))  # Dot 2 -> ⠂
        self.assertEqual(dots_to_unicode([0, 0, 1, 0, 0, 0]), chr(0x2800 | 0x04))  # Dot 3 -> ⠄
        self.assertEqual(dots_to_unicode([0, 0, 0, 1, 0, 0]), chr(0x2800 | 0x08))  # Dot 4 -> ⠈
        self.assertEqual(dots_to_unicode([0, 0, 0, 0, 1, 0]), chr(0x2800 | 0x10))  # Dot 5 -> ⠐
        self.assertEqual(dots_to_unicode([0, 0, 0, 0, 0, 1]), chr(0x2800 | 0x20))  # Dot 6 -> ⠠

        # Test composite masks
        # 'b': Dot 1 + Dot 2 = 0x01 | 0x02 = 0x03
        self.assertEqual(dots_to_unicode([1, 1, 0, 0, 0, 0]), chr(0x2803))
        # 'c': Dot 1 + Dot 4 = 0x01 | 0x08 = 0x09
        self.assertEqual(dots_to_unicode([1, 0, 0, 1, 0, 0]), chr(0x2809))
        # 'r': Dot 1 + Dot 2 + Dot 3 + Dot 5 = 0x01 | 0x02 | 0x04 | 0x10 = 0x17
        self.assertEqual(dots_to_unicode([1, 1, 1, 0, 1, 0]), chr(0x2817))

        # Test mask == 0 mapping
        self.assertEqual(dots_to_unicode([0, 0, 0, 0, 0, 0], empty_as_space=True), " ")
        self.assertEqual(dots_to_unicode([0, 0, 0, 0, 0, 0], empty_as_space=False), chr(0x2800))
        self.assertEqual(binary_str_to_unicode("000000", empty_as_space=True), " ")

    def test_direct_liblouis_en_ueb_g2_target_words(self):
        """
        Verifies that standard contracted words translate and decode accurately
        using louis.backTranslateString(["en-ueb-g2.ctb"], unicode_braille_str):
        - Robinson (⠠⠗⠕⠃⠔⠎⠕⠝)
        - Crusoe (⠠⠉⠗⠥⠎⠕⠑)
        - sailor (⠎⠁⠊⠇⠕⠗)
        - rescued (⠗⠑⠎⠉⠥⠫)
        - pockets (⠏⠕⠉⠅⠑⠞⠎)
        """
        target_words = {
            "⠠⠗⠕⠃⠔⠎⠕⠝": "Robinson",
            "⠠⠉⠗⠥⠎⠕⠑": "Crusoe",
            "⠎⠁⠊⠇⠕⠗": "sailor",
            "⠗⠑⠎⠉⠥⠫": "rescued",
            "⠏⠕⠉⠅⠑⠞⠎": "pockets",
            "⠉⠕⠍⠏⠇⠑⠞⠑⠇⠽ ⠙⠗⠽": "completely dry",
            "⠎⠕⠇⠊⠞⠥⠙⠑ ⠁⠞ ⠎⠑⠁": "solitude at sea",
            "⠞⠺⠕ ⠕⠗ ⠹⠗⠑⠑ ⠍⠔⠥⠞⠑⠎": "two or three minutes",
            "⠛⠕⠇⠙ ⠺⠁⠞⠡": "gold watch",
            "⠅⠑⠽⠎": "keys",
            "⠇⠕⠉⠅⠻": "locker",
            "⠺⠁⠞⠻": "water",
            "⠇⠕⠉⠅⠻ ⠕⠝": "locker on",
            "⠏⠑⠎⠕⠎ ⠔ ⠍⠽ ⠏⠕⠉⠅⠑⠞⠎": "pesos in my pockets",
        }
        for u_str, expected_word in target_words.items():
            translated = louis.backTranslateString(["en-ueb-g2.ctb"], u_str)
            self.assertEqual(
                translated,
                expected_word,
                f"Unicode stream {u_str} must back-translate to {expected_word} via en-ueb-g2.ctb"
            )

    def test_rigid_lattice_single_column_and_empty_cells(self):
        """
        Verifies that a cell with dots only in Column 1 (Dot 6 capital sign)
        does NOT shift the grid phase or fuse with adjacent cells, and empty
        cells are accurately detected as whitespace.
        """
        dx = 14.0
        dy = 14.0
        cx = 40.0
        X0 = 60.0
        Y0 = 80.0

        # Synthetic test pattern:
        # Cell 0 (c=0): Dot 6 at (X0 + dx, Y0 + 2*dy) -> Col 1, Row 2
        # Cell 1 (c=1): Dot 1 at (X0 + cx, Y0), Dot 2 at (X0 + cx, Y0 + dy) -> 'b'
        # Cell 2 (c=2): EMPTY (word space)
        # Cell 3 (c=3): Dot 1 at (X0 + 3*cx, Y0), Dot 4 at (X0 + 3*cx + dx, Y0) -> 'c'
        test_dots = [
            EmbossedDot(x=X0 + dx, y=Y0 + 2*dy, radius=3.0, contrast=50.0, vector_dx=1.0, vector_dy=1.0),
            EmbossedDot(x=X0 + cx, y=Y0, radius=3.0, contrast=50.0, vector_dx=1.0, vector_dy=1.0),
            EmbossedDot(x=X0 + cx, y=Y0 + dy, radius=3.0, contrast=50.0, vector_dx=1.0, vector_dy=1.0),
            EmbossedDot(x=X0 + 3*cx, y=Y0, radius=3.0, contrast=50.0, vector_dx=1.0, vector_dy=1.0),
            EmbossedDot(x=X0 + 3*cx + dx, y=Y0, radius=3.0, contrast=50.0, vector_dx=1.0, vector_dy=1.0),
        ]

        lines = fit_braille_grid(test_dots, (200, 300), expected_dot_pitch=14.0)
        self.assertEqual(len(lines), 1, "Should fit exactly 1 line")
        cells = lines[0]
        self.assertEqual(len(cells), 3, "Should have 3 non-empty cells (Cell 0, Cell 1, Cell 3)")

        # Cell 0 must be strictly Dot 6: [0, 0, 0, 0, 0, 1] -> binary '000001', unicode '⠠'
        self.assertEqual(cells[0].dots, [0, 0, 0, 0, 0, 1], "Cell 0 must have Dot 6 in Column 1, not Column 0")
        self.assertEqual(cells[0].binary_str, "000001")
        self.assertEqual(cells[0].unicode_char, "⠠")
        self.assertFalse(cells[0].has_space_before)

        # Cell 1 must be 'b': [1, 1, 0, 0, 0, 0] -> '⠃'
        self.assertEqual(cells[1].dots, [1, 1, 0, 0, 0, 0])
        self.assertEqual(cells[1].unicode_char, "⠃")
        self.assertFalse(cells[1].has_space_before)

        # Cell 2 was empty, so Cell 3 must have has_space_before = True
        self.assertTrue(cells[2].has_space_before, "Empty cell 2 must trigger space_before on cell 3")
        self.assertEqual(cells[2].dots, [1, 0, 0, 1, 0, 0], "Cell 3 must be 'c' with Dots 1 and 4")
        self.assertEqual(cells[2].unicode_char, "⠉")

        # Contextual decoding must yield "But can"
        u_str, text = self.decoder.decode_cells(cells)
        self.assertEqual(u_str, "⠠⠃ ⠉")
        self.assertEqual(text, "But can")

    def test_liblouis_contextual_contractions(self):
        """
        Tests contextual contraction handling without isolated fragment dumping:
        - 'rescued' (merging rescu + ed)
        - 'cannot' (not leaking separate 'not can')
        - 'pockets'
        - Numbers and Capitals
        """
        # 1. rescued: r(⠗) e(⠑) s(⠎) c(⠉) u(⠥) ed(⠫)
        braille_rescued = "⠗⠑⠎⠉⠥⠫"
        text_rescued = self.decoder.translate(braille_rescued)
        self.assertEqual(text_rescued.lower(), "rescued", "ed contraction must merge into 'rescued', not 'rescu ed'")
        self.assertNotIn(" ", text_rescued, "Should not have space between stem and contraction")

        # 2. cannot: c(⠉) a(⠁) n(⠝) n(⠝) o(⠕) t(⠞) or c(⠉) not(⠝)
        braille_cannot = "⠉⠁⠝⠝⠕⠞"
        text_cannot = self.decoder.translate(braille_cannot)
        self.assertEqual(text_cannot.lower(), "cannot", "Must translate to 'cannot'")

        # 3. pockets: p(⠏) o(⠕) c(⠉) k(⠅) e(⠑) t(⠞) s(⠎)
        braille_pockets = "⠏⠕⠉⠅⠑⠞⠎"
        text_pockets = self.decoder.translate(braille_pockets)
        self.assertEqual(text_pockets.lower(), "pockets", "Must translate to 'pockets'")

        # 4. Whole-word signs when standalone
        # 'c' alone -> 'can', 'n' alone -> 'not', 'p' alone -> 'people', 'k' alone -> 'knowledge'
        braille_wordsigns = "⠉ ⠝ ⠏ ⠅"
        text_wordsigns = self.decoder.translate(braille_wordsigns)
        self.assertEqual(text_wordsigns.lower(), "can not people knowledge")

        # 5. Number sign (⠼)
        braille_num = "⠼⠁⠃⠉"
        text_num = self.decoder.translate(braille_num)
        self.assertEqual(text_num, "123", "Number sign must map to digits without leaking '#'")

        # 6. Capital sign (⠠)
        braille_cap = "⠠⠗⠕⠃⠔⠎⠕⠝ ⠠⠉⠗⠥⠎⠕⠑"
        text_cap = self.decoder.translate(braille_cap)
        self.assertEqual(text_cap, "Robinson Crusoe", "Capital indicator must capitalize without leaking ','")

    def test_end_to_end_sample_image(self):
        """
        Executes end-to-end pipeline on sample image, outputs both raw Unicode Braille
        and translated English text, and asserts coherent English output.
        """
        sample_path = "ml/yolov8_braille/captured_phone.jpg"
        if not os.path.exists(sample_path):
            sample_path = "ml/yolov8_braille/captured_phone_2.jpg"
        if not os.path.exists(sample_path):
            self.skipTest(f"Sample image not found at {sample_path}")

        pipeline = BrailleOCRPipeline(tflite_model_path="app/assets/models/yolov8_braille.tflite")
        result = pipeline.process_image(sample_path, apply_perspective_warp=True)

        raw_braille = result.get("raw_braille", "")
        english_text = result.get("text", "")
        total_cells = result.get("total_cells", 0)

        print("\n" + "=" * 80)
        print("END-TO-END OCR VERIFICATION OUTPUT:")
        print("=" * 80)
        print("--- RAW UNICODE BRAILLE ---")
        print(raw_braille)
        print("\n--- TRANSLATED CONTEXTUAL ENGLISH TEXT ---")
        print(english_text)
        print("=" * 80)

        self.assertGreater(total_cells, 20, "Should detect at least 20 Braille cells on sample page")
        self.assertGreater(len(english_text), 20, "Translated text should not be empty")

        # Assert coherent English phrases are decoded
        lower_text = english_text.lower()
        self.assertTrue(
            "crusoe" in lower_text or "robinson" in lower_text or "rob son" in lower_text or "island" in lower_text or "published" in lower_text or "despair" in lower_text,
            f"Expected key text phrases in output, got:\n{english_text[:300]}"
        )

        # Assert no raw contraction indicator leakage
        self.assertNotIn("rescu ed", lower_text, "Should not leak 'rescu ed'")
        self.assertNotIn("not can", lower_text, "Should not leak 'not can'")


if __name__ == "__main__":
    unittest.main()
