"""
Refactored Auto-Orientation, Rigid Lattice Grid, and Contextual Grade 2 Liblouis Decoding Test.
Uses the BrailleOCRPipeline to handle:
1. Perspective skew rectification (warpPerspective)
2. Automatic 4-way orientation detection (0°, 90°, 180°, 270°) using shadow gradient vectors and cell distribution scoring
3. Rigid lattice global grid fitting with zero half-cell phase drift
4. Contextual Grade 2 back-translation via Liblouis
"""

import sys
import os

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))
from PIL import Image, ImageOps

from ml.braille_ocr.pipeline import BrailleOCRPipeline


def run_pipeline_test(img_path="ml/yolov8_braille/captured_phone_2.jpg", invert_first=False):
    print("=" * 80)
    print(f"RUNNING BRAILLE OCR PIPELINE: {img_path} (invert_first={invert_first})")
    print("=" * 80)

    if not os.path.exists(img_path):
        print(f"File not found: {img_path}")
        return

    # Load image
    orig = Image.open(img_path)
    baked = ImageOps.exif_transpose(orig)
    if invert_first:
        print("[TEST MODE] Intentionally inverting test image by 180°...")
        input_image = baked.rotate(180, expand=True)
    else:
        input_image = baked

    pipeline = BrailleOCRPipeline(tflite_model_path="app/assets/models/yolov8_braille.tflite")
    result = pipeline.process_image(input_image, apply_perspective_warp=True)

    applied_rot = result['orientation_applied']
    metrics = result['orientation_metrics']
    text = result['text']
    raw_braille = result.get('raw_braille', '')
    total_cells = result['total_cells']
    method = result['method']

    print(f"\n--- ORIENTATION METRICS ---")
    for rot, m in metrics.items():
        print(f"Rotation {rot:3d}° -> Total Score: {m['total']:6.1f} (aspect: {m['aspect_score']:+.2f}, dist: {m['dist_score']:6.1f}, shadow_score: {m['shadow_score']:+2.0f})")

    print(f"\nSelected Best Orientation: {applied_rot}°")
    print(f"Segmentation Method: {method}")
    print(f"Total Braille Cells Detected: {total_cells}")

    print("\n" + "=" * 80)
    print("RAW UNICODE BRAILLE PATTERNS (U+2800..U+28FF):")
    print("=" * 80)
    print(raw_braille)

    print("\n" + "=" * 80)
    print("FINAL CONTEXTUAL GRADE 2 TRANSLATED TEXT (LIBLOUIS):")
    print("=" * 80)
    print(text)
    print("=" * 80)

    print("\n" + "=" * 80)
    print("VERIFICATION OF TARGET LINES (LINE 7 & LINE 14):")
    print("=" * 80)
    raw_lines = raw_braille.splitlines()
    text_lines = text.splitlines()
    if len(raw_lines) > 7 and len(text_lines) > 7:
        print(f"Line 07 | Braille: {raw_lines[7]} | English: {text_lines[7]}")
    if len(raw_lines) > 14 and len(text_lines) > 14:
        print(f"Line 14 | Braille: {raw_lines[14]} | English: {text_lines[14]}")

    # Explicit verification of Grade 2 target benchmark phrases
    from ml.braille_ocr import louis
    benchmarks = {
        "completely dry": "⠉⠕⠍⠏⠇⠑⠞⠑⠇⠽ ⠙⠗⠽",
        "solitude at sea": "⠎⠕⠇⠊⠞⠥⠙⠑ ⠁⠞ ⠎⠑⠁",
        "two or three minutes": "⠞⠺⠕ ⠕⠗ ⠹⠗⠑⠑ ⠍⠔⠥⠞⠑⠎",
        "gold watch": "⠛⠕⠇⠙ ⠺⠁⠞⠡",
        "keys": "⠅⠑⠽⠎",
        "locker": "⠇⠕⠉⠅⠻",
        "rescued": "⠗⠑⠎⠉⠥⠫",
        "pesos in my pockets": "⠏⠑⠎⠕⠎ ⠔ ⠍⠽ ⠏⠕⠉⠅⠑⠞⠎",
        "water": "⠺⠁⠞⠻",
        "locker on": "⠇⠕⠉⠅⠻ ⠕⠝",
    }
    print("\n--- GRADE 2 LIBLOUIS CONTIGUOUS PHRASE VERIFICATION ---")
    for expected, u_code in benchmarks.items():
        trans = louis.backTranslateString(['en-ueb-g2.ctb'], u_code)
        status = "PASS" if trans == expected else "FAIL"
        print(f"[{status}] {expected:22s} | Braille: {u_code:25s} -> Liblouis: '{trans}'")
    print("=" * 80)
    return result


if __name__ == '__main__':
    # Test standard orientation on captured_phone.jpg
    if os.path.exists("ml/yolov8_braille/captured_phone.jpg"):
        run_pipeline_test("ml/yolov8_braille/captured_phone.jpg", invert_first=False)
    elif os.path.exists("ml/yolov8_braille/captured_phone_2.jpg"):
        run_pipeline_test("ml/yolov8_braille/captured_phone_2.jpg", invert_first=False)
