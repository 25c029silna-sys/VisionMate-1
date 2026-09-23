import sys
import os
import io

sys.path.insert(0, os.path.abspath("."))
from ml.braille_ocr.pipeline import BrailleOCRPipeline

def main():
    pipe = BrailleOCRPipeline(tflite_model_path="app/assets/models/yolov8_braille.tflite")
    res = pipe.process_image("ml/yolov8_braille/captured_phone.jpg", prefer_geometric=False, export_debug_image=False)
    
    raw_lines = res["raw_braille"].splitlines()
    text_lines = res["text"].splitlines()
    
    print(f"Total lines: {len(raw_lines)}")
    for i, (b_line, t_line) in enumerate(zip(raw_lines, text_lines)):
        print(f"Line {i:02d} | Braille: {b_line} | English: {t_line}")

if __name__ == "__main__":
    main()
