import sys
import os
sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, 'ml')

from braille_ocr.pipeline import BrailleOCRPipeline

pipeline = BrailleOCRPipeline(tflite_model_path="app/assets/models/yolov8_braille.tflite")
res = pipeline.process_image("ml/yolov8_braille/captured_phone_2.jpg")

print(f"Total lines: {len(res['grid_lines'])}")
for i, line in enumerate(res['grid_lines'][:5]):
    raw_braille = "".join(c.unicode_char for c in line)
    classes = [c.class_index for c in line]
    binaries = [c.binary_str for c in line]
    print(f"--- Line {i} ---")
    print(f"Unicode Braille: {raw_braille}")
    print(f"Classes: {classes}")
    print(f"Binaries: {binaries}")
    for idx, c in enumerate(line):
        print(f"  [{idx}] class={c.class_index:2d} bin={c.binary_str} dots={c.dots} uni={c.unicode_char!r} U+{ord(c.unicode_char):04X} space_before={c.has_space_before}")
