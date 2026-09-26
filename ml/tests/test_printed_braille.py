"""
Unit and Integration Test Suite for Non-Embossed (Printed/Flat) Braille Recognition.
Verifies:
1. Dark-on-light printed dot detection with circularity and contrast filtering.
2. Light-on-dark (inverted digital) dot detection via automatic polarity discovery.
3. Linear and non-circular noise rejection.
4. End-to-end pipeline execution in 'printed' mode.
5. End-to-end pipeline execution in 'auto' mode.
"""

import sys
import unittest
import numpy as np
import cv2

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

from ml.braille.dot_detection import (
    detect_printed_braille_dots,
    detect_braille_dots,
)
from ml.braille.pipeline import BrailleRecognitionPipeline
from ml.braille.braille_decoder import BRAILLE_MAP_GRADE1


# Standard 2x3 column-major mapping:
# Dot 1: (row 0, col 0), Dot 2: (row 1, col 0), Dot 3: (row 2, col 0)
# Dot 4: (row 0, col 1), Dot 5: (row 1, col 1), Dot 6: (row 2, col 1)
LETTER_TO_DOTS = {
    'a': [1],
    'b': [1, 2],
    'c': [1, 4],
    'd': [1, 4, 5],
    'e': [1, 5],
    'f': [1, 2, 4],
    'g': [1, 2, 4, 5],
    'h': [1, 2, 5],
    'i': [2, 4],
    'j': [2, 4, 5],
    'k': [1, 3],
    'l': [1, 2, 3],
    'm': [1, 3, 4],
    'n': [1, 3, 4, 5],
    'o': [1, 3, 5],
    'p': [1, 2, 3, 4],
    'q': [1, 2, 3, 4, 5],
    'r': [1, 2, 3, 5],
    's': [2, 3, 4],
    't': [2, 3, 4, 5],
    'u': [1, 3, 6],
    'v': [1, 2, 3, 6],
    'w': [2, 4, 5, 6],
    'x': [1, 3, 4, 6],
    'y': [1, 3, 4, 5, 6],
    'z': [1, 3, 5, 6],
}


def render_printed_braille_text(
    text: str,
    dot_radius: int = 4,
    dx: int = 14,
    dy: int = 14,
    cx: int = 42,
    margin_x: int = 40,
    margin_y: int = 40,
    inverted: bool = False
) -> np.ndarray:
    """
    Renders a synthetic image containing printed Braille dots for given text.
    """
    total_cells = len(text)
    w = margin_x * 2 + total_cells * cx + 60
    h = margin_y * 2 + 3 * dy + 60

    bg_val = 0 if inverted else 255
    dot_val = 255 if inverted else 0
    img = np.full((h, w, 3), bg_val, dtype=np.uint8)

    cur_x = margin_x
    for char in text.lower():
        if char == ' ':
            cur_x += cx
            continue

        dots = LETTER_TO_DOTS.get(char, [])
        for dot_num in dots:
            if dot_num in (1, 2, 3):
                col = 0
                row = dot_num - 1
            else:
                col = 1
                row = dot_num - 4

            dot_x = cur_x + col * dx
            dot_y = margin_y + row * dy
            cv2.circle(img, (int(dot_x), int(dot_y)), dot_radius, (dot_val, dot_val, dot_val), -1)

        cur_x += cx

    return img


class TestPrintedBrailleRecognition(unittest.TestCase):

    def test_printed_dot_detection_dark_on_light(self):
        """Verifies accurate detection of black circular ink dots on white background."""
        img = np.full((120, 120, 3), 255, dtype=np.uint8)
        # Draw letter 'd' (dots 1, 4, 5)
        # dot 1: (40, 30), dot 4: (54, 30), dot 5: (54, 44)
        cv2.circle(img, (40, 30), 4, (0, 0, 0), -1)
        cv2.circle(img, (54, 30), 4, (0, 0, 0), -1)
        cv2.circle(img, (54, 44), 4, (0, 0, 0), -1)

        dots = detect_printed_braille_dots(img, min_radius=2.0, max_radius=10.0)
        self.assertEqual(len(dots), 3, f"Expected 3 dots, got {len(dots)}")

        centers = [(d["x"], d["y"]) for d in dots]
        for target_x, target_y in [(40, 30), (54, 30), (54, 44)]:
            matched = any(abs(cx - target_x) <= 2.0 and abs(cy - target_y) <= 2.0 for cx, cy in centers)
            self.assertTrue(matched, f"Target dot ({target_x}, {target_y}) not detected accurately: {centers}")

        for d in dots:
            self.assertGreater(d["confidence"], 0.70)
            self.assertGreater(d["circularity"], 0.65)

    def test_printed_dot_detection_light_on_dark(self):
        """Verifies automatic polarity detection for white dots on black background."""
        img = np.full((120, 120, 3), 10, dtype=np.uint8)
        # Draw letter 'b' (dots 1, 2)
        cv2.circle(img, (40, 30), 4, (245, 245, 245), -1)
        cv2.circle(img, (40, 46), 4, (245, 245, 245), -1)

        dots = detect_printed_braille_dots(img, polarity="auto")
        self.assertEqual(len(dots), 2, f"Expected 2 dots, got {len(dots)}")
        for d in dots:
            self.assertGreater(d["confidence"], 0.70)

    def test_noise_rejection(self):
        """Verifies that non-circular lines, text strokes, and speckle noise are rejected."""
        img = np.full((150, 150, 3), 255, dtype=np.uint8)
        # Add 1 valid Braille dot
        cv2.circle(img, (40, 40), 4, (0, 0, 0), -1)

        # Add horizontal line (scratch/underline)
        cv2.line(img, (20, 90), (120, 90), (0, 0, 0), thickness=2)

        # Add elongated rectangle
        cv2.rectangle(img, (70, 20), (74, 60), (0, 0, 0), -1)

        dots = detect_printed_braille_dots(img, min_circularity=0.60)
        self.assertEqual(len(dots), 1, f"Expected exactly 1 dot after noise rejection, got {len(dots)}")
        self.assertAlmostEqual(dots[0]["x"], 40.0, delta=2.0)
        self.assertAlmostEqual(dots[0]["y"], 40.0, delta=2.0)

    def test_pipeline_printed_mode_single_word(self):
        """Verifies end-to-end decoding of a synthetic printed Braille word ('cab')."""
        img = render_printed_braille_text("cab")
        pipeline = BrailleRecognitionPipeline(dot_mode="printed", enable_language_correction=False)
        res = pipeline.process(img, apply_perspective_warp=False, auto_orient=False)

        self.assertEqual(res["status"], "success")
        self.assertEqual(res["dot_mode"], "printed")
        self.assertEqual(res["raw_decoded_text"].strip(), "cab")

    def test_pipeline_auto_mode_printed_word(self):
        """Verifies that auto mode successfully selects printed pipeline and decodes ('hello')."""
        img = render_printed_braille_text("hello")
        pipeline = BrailleRecognitionPipeline(dot_mode="auto", enable_language_correction=False)
        res = pipeline.process(img, apply_perspective_warp=False, auto_orient=False)

        self.assertEqual(res["status"], "success")
        self.assertEqual(res["raw_decoded_text"].strip(), "hello")


if __name__ == "__main__":
    unittest.main()
