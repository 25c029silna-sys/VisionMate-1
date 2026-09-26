"""
Demo and Rapid Prototyping Script for Non-Embossed (Printed/Flat) Braille Recognition.

Usage:
    python scratch/demo_printed_braille.py --text "hello world" --output debug/printed_demo.png
    python scratch/demo_printed_braille.py --image path/to/image.png
"""

import os
import sys
import argparse
import cv2
import numpy as np

# Ensure project root is on sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

from ml.braille.pipeline import BrailleRecognitionPipeline
from ml.tests.test_printed_braille import render_printed_braille_text


def main():
    parser = argparse.ArgumentParser(description="VisionMate Printed Braille Recognition Demo")
    parser.add_argument("--text", type=str, default="braille recognition", help="Text to synthesize into printed Braille")
    parser.add_argument("--image", type=str, default=None, help="Optional path to existing printed Braille image")
    parser.add_argument("--inverted", action="store_true", help="Synthesize white dots on black background")
    parser.add_argument("--debug-dir", type=str, default="debug/printed_demo", help="Directory for debug outputs")
    parser.add_argument("--mode", type=str, default="printed", choices=["printed", "auto", "embossed"], help="Dot mode")

    args = parser.parse_args()
    os.makedirs(args.debug_dir, exist_ok=True)

    if args.image and os.path.exists(args.image):
        print(f"[Demo] Loading image: {args.image}")
        img = cv2.imread(args.image)
        stem = os.path.splitext(os.path.basename(args.image))[0]
    else:
        print(f"[Demo] Synthesizing printed Braille for text: '{args.text}' (inverted={args.inverted})")
        img = render_printed_braille_text(args.text, inverted=args.inverted)
        synth_path = os.path.join(args.debug_dir, "00_synthesized_input.png")
        cv2.imwrite(synth_path, img)
        print(f"[Demo] Saved synthesized image to: {synth_path}")
        stem = "synthetic_card"

    pipeline = BrailleRecognitionPipeline(
        dot_mode=args.mode,
        enable_language_correction=False
    )

    print(f"[Demo] Running BrailleRecognitionPipeline (mode={args.mode})...")
    res = pipeline.process(
        img,
        apply_perspective_warp=False,
        auto_orient=False,
        debug=True,
        debug_dir=args.debug_dir,
        filename_stem=stem
    )

    print("\n" + "=" * 50)
    print("           RECOGNITION RESULTS")
    print("=" * 50)
    print(f"Status:               {res.get('status')}")
    print(f"Active Dot Mode:      {res.get('dot_mode')}")
    print(f"Detected Dots:        {res.get('detected_dots_count')}")
    print(f"Detected Cells:       {res.get('detected_cells_count')}")
    print(f"Decoded Raw Braille:  {res.get('raw_braille')}")
    print(f"Decoded Text:         {res.get('raw_decoded_text')}")
    print(f"Visualization Artifact: {res.get('visualization_path')}")
    print("=" * 50 + "\n")


if __name__ == "__main__":
    main()
