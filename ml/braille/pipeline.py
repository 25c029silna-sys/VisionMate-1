"""
VisionMate Modular Braille Recognition Pipeline.
Coordinates end-to-end execution:
1. Image validation
2. Perspective correction / page rectification
3. Grayscale conversion
4. Illumination correction
5. Local contrast enhancement
6. Embossed-dot enhancement
7. Braille dot detection
8. Braille cell reconstruction
9. 6-dot pattern extraction
10. Braille pattern -> character decoding
11. Word/line reconstruction
12. Optional language-level correction
"""

import os
import sys
import argparse
import cv2
import numpy as np
from PIL import Image, ImageOps
from typing import Union, Dict, Any, List, Optional, Tuple

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

from .preprocessing import (
    preprocess_image,
    evaluate_preprocessing_candidates,
    PREPROCESS_METHOD_COMBINED,
    PREPROCESS_METHOD_CLAHE,
    PREPROCESS_METHOD_BLACKHAT,
    PREPROCESS_METHOD_GRADIENT,
    PREPROCESS_METHOD_PRINTED,
)
from .perspective import (
    rectify_page_perspective,
    normalize_orientation,
)
from .dot_detection import (
    detect_embossed_braille_dots,
    detect_printed_braille_dots,
    detect_braille_dots,
)
from .cell_segmentation import (
    segment_dots_into_cells,
    estimate_pitches,
    BrailleCellCandidate,
)
from .visualization import (
    visualize_cells_and_dots,
    export_cell_diagnostics,
)
from .braille_decoder import (
    decode_line_grade1,
    decode_line_grade2_liblouis,
    pattern_to_unicode,
)
from .text_reconstruction import (
    reconstruct_text_from_cells,
)
from .error_analysis import (
    analyze_cell_confidences,
)


class BrailleRecognitionPipeline:
    """
    Modular, transparent Braille recognition pipeline for photographed embossed pages.
    """

    def __init__(
        self,
        dot_mode: str = "auto",
        default_preprocess_method: str = PREPROCESS_METHOD_COMBINED,
        use_grade2: bool = False,
        enable_language_correction: bool = True,
        clip_limit: float = 2.5,
        kernel_size: int = 11
    ):
        self.dot_mode = dot_mode
        if dot_mode == "printed" and default_preprocess_method == PREPROCESS_METHOD_COMBINED:
            self.preprocess_method = PREPROCESS_METHOD_PRINTED
        else:
            self.preprocess_method = default_preprocess_method
        self.use_grade2 = use_grade2
        self.enable_language_correction = enable_language_correction
        self.clip_limit = clip_limit
        self.kernel_size = kernel_size

        # Lazy load optional language model
        self.language_model = None
        if enable_language_correction:
            try:
                from .language_model import BrailleLanguageModel
                self.language_model = BrailleLanguageModel()
            except Exception:
                try:
                    from ..braille_ocr.language_model import BrailleLanguageModel
                    self.language_model = BrailleLanguageModel()
                except Exception:
                    self.language_model = None

    def validate_and_load_image(
        self,
        image_input: Union[str, np.ndarray, Image.Image]
    ) -> np.ndarray:
        """
        Step 1: Image validation and ingestion.
        Bakes camera EXIF orientation tags and converts to BGR uint8 NumPy array.
        """
        if isinstance(image_input, str):
            if not os.path.exists(image_input):
                raise FileNotFoundError(f"Input image not found: {image_input}")
            pil_img = Image.open(image_input)
            pil_img = ImageOps.exif_transpose(pil_img)
            bgr = cv2.cvtColor(np.array(pil_img.convert("RGB")), cv2.COLOR_RGB2BGR)
        elif isinstance(image_input, Image.Image):
            pil_img = ImageOps.exif_transpose(image_input)
            bgr = cv2.cvtColor(np.array(pil_img.convert("RGB")), cv2.COLOR_RGB2BGR)
        elif isinstance(image_input, np.ndarray):
            bgr = image_input.copy()
        else:
            raise ValueError(f"Unsupported image input type: {type(image_input)}")

        if bgr.size == 0 or len(bgr.shape) < 2:
            raise ValueError("Input image is empty or invalid.")

        return bgr

    def process(
        self,
        image_input: Union[str, np.ndarray, Image.Image],
        apply_perspective_warp: bool = True,
        auto_orient: bool = True,
        preprocess_method: Optional[str] = None,
        dot_mode: Optional[str] = None,
        debug: bool = False,
        debug_dir: str = "debug",
        filename_stem: str = "braille_sample",
        milestone_only: bool = False
    ) -> Dict[str, Any]:
        """
        Executes the complete recognition pipeline.
        """
        # Step 1: Image validation & load
        raw_bgr = self.validate_and_load_image(image_input)
        h_orig, w_orig = raw_bgr.shape[:2]

        if debug:
            os.makedirs(debug_dir, exist_ok=True)
            cv2.imwrite(os.path.join(debug_dir, "01_original.png"), raw_bgr)

        # Step 2: Perspective correction / page rectification
        if apply_perspective_warp:
            rectified_bgr, warp_m, was_rectified = rectify_page_perspective(raw_bgr)
        else:
            rectified_bgr = raw_bgr.copy()
            warp_m = np.eye(3, dtype=np.float32)
            was_rectified = False

        if auto_orient:
            best_rot, upright_bgr, orient_metrics = normalize_orientation(rectified_bgr)
        else:
            best_rot = 0
            upright_bgr = rectified_bgr.copy()
            orient_metrics = {"best_angle": 0}

        if debug:
            cv2.imwrite(os.path.join(debug_dir, "02_rectified.png"), upright_bgr)

        # Steps 3, 4, 5, 6: Multi-method Preprocessing
        effective_dot_mode = dot_mode or self.dot_mode
        if effective_dot_mode == "printed" and preprocess_method is None and self.preprocess_method == PREPROCESS_METHOD_COMBINED:
            method_to_use = PREPROCESS_METHOD_PRINTED
        else:
            method_to_use = preprocess_method or self.preprocess_method

        prep = preprocess_image(
            upright_bgr,
            method=method_to_use,
            clip_limit=self.clip_limit,
            kernel_size=self.kernel_size,
            normalize_light=True
        )

        if debug:
            cv2.imwrite(os.path.join(debug_dir, "03_grayscale.png"), prep["grayscale"])
            cv2.imwrite(os.path.join(debug_dir, "04_contrast.png"), prep["contrast_enhanced"])
            cv2.imwrite(os.path.join(debug_dir, "05_dot_enhanced.png"), prep["enhanced"])
            cv2.imwrite(os.path.join(debug_dir, "06_threshold.png"), prep["threshold"])

        # Step 7: Braille dot detection
        dots = detect_braille_dots(
            upright_bgr,
            mode=effective_dot_mode,
            tophat=prep["tophat"],
            blackhat=prep["blackhat"],
            min_radius=2.0,
            max_radius=14.0,
            min_contrast=6.0
        )

        if debug:
            dots_canvas = upright_bgr.copy()
            for d in dots:
                cv2.circle(dots_canvas, (int(round(d["x"])), int(round(d["y"]))), int(round(d["radius"])), (0, 255, 0), -1)
            cv2.imwrite(os.path.join(debug_dir, "07_detected_dots.png"), dots_canvas)

        # Step 8 & 9: Braille cell reconstruction and 6-dot pattern extraction
        grid_lines = segment_dots_into_cells(
            dots=dots,
            image_shape=upright_bgr.shape,
            relief_map=prep["enhanced"]
        )

        # Step 7 (Visual): Cell Visualization
        diag_cells_path = os.path.join(debug_dir, f"cells_{filename_stem}.png")
        visualize_cells_and_dots(upright_bgr, dots, grid_lines, output_path=diag_cells_path)

        if debug:
            cv2.imwrite(os.path.join(debug_dir, "08_cells.png"), cv2.imread(diag_cells_path))

        # Pitch & Dimension statistics
        if dots:
            dx, dy, cx = estimate_pitches(dots)
        else:
            dx, dy, cx = 14.0, 14.0, 42.0

        all_cells = [c for line in grid_lines for c in line]
        avg_cell_w = float(np.mean([c.x2 - c.x1 for c in all_cells])) if all_cells else (dx + cx / 2.0)
        avg_cell_h = float(np.mean([c.y2 - c.y1 for c in all_cells])) if all_cells else (3.0 * dy)

        confidence_info = analyze_cell_confidences(grid_lines)

        # Milestone exit gate: if milestone_only, return visual artifacts immediately
        if milestone_only:
            return {
                "status": "milestone_ready",
                "image_size": (upright_bgr.shape[1], upright_bgr.shape[0]),
                "detected_dots_count": len(dots),
                "detected_cells_count": len(all_cells),
                "total_lines": len(grid_lines),
                "average_dot_spacing": round(float(dx), 2),
                "average_cell_width": round(avg_cell_w, 2),
                "average_cell_height": round(avg_cell_h, 2),
                "mean_confidence": confidence_info["mean_confidence"],
                "visualization_path": diag_cells_path,
                "preprocess_method": method_to_use,
                "dot_mode": effective_dot_mode,
                "rectified_image": upright_bgr,
                "dots": dots,
                "grid_lines": grid_lines
            }

        # Step 10 & 11: Braille pattern -> character decoding and word/line reconstruction
        reconstructed = reconstruct_text_from_cells(
            grid_lines,
            use_grade2=self.use_grade2
        )

        raw_braille = reconstructed["raw_braille"]
        raw_text = reconstructed["raw_decoded_text"]

        # Step 12: Optional language-level correction
        corrected_text = raw_text
        if self.enable_language_correction and self.language_model is not None:
            try:
                corrected_text = self.language_model.refine(raw_text)
            except Exception as e:
                print(f"[BrailleRecognitionPipeline] Language model notice: {e}")
                corrected_text = raw_text

        if debug:
            txt_path = os.path.join(debug_dir, "09_decoded_text.txt")
            with open(txt_path, "w", encoding="utf-8") as f:
                f.write("=== RAW BRAILLE DECODE ===\n")
                f.write(raw_braille + "\n\n")
                f.write("=== RAW DECODED TEXT ===\n")
                f.write(raw_text + "\n\n")
                f.write("=== CORRECTED TEXT ===\n")
                f.write(corrected_text + "\n")

        return {
            "status": "success",
            "image_size": (upright_bgr.shape[1], upright_bgr.shape[0]),
            "detected_dots_count": len(dots),
            "detected_cells_count": len(all_cells),
            "total_lines": reconstructed["total_lines"],
            "total_words": reconstructed["total_words"],
            "average_dot_spacing": round(float(dx), 2),
            "average_cell_width": round(avg_cell_w, 2),
            "average_cell_height": round(avg_cell_h, 2),
            "mean_confidence": confidence_info["mean_confidence"],
            "raw_braille": raw_braille,
            "raw_decoded_text": raw_text,
            "corrected_text": corrected_text,
            "preprocess_method": method_to_use,
            "dot_mode": effective_dot_mode,
            "confidence_info": confidence_info,
            "visualization_path": diag_cells_path,
            "grid_lines": grid_lines
        }


def print_statistics(res: Dict[str, Any]):
    """Pretty prints statistics required by Section 13."""
    print("\n" + "=" * 55)
    print("      BRAILLE RECOGNITION PIPELINE STATISTICS")
    print("=" * 55)
    print(f"Image size:             {res.get('image_size', (0,0))[0]} x {res.get('image_size', (0,0))[1]} px")
    print(f"Number of detected dots:  {res.get('detected_dots_count', 0)}")
    print(f"Number of detected cells: {res.get('detected_cells_count', 0)}")
    print(f"Number of lines:          {res.get('total_lines', 0)}")
    print(f"Number of words:          {res.get('total_words', 0)}")
    print(f"Average dot spacing:      {res.get('average_dot_spacing', 0.0):.2f} px")
    print(f"Average cell width:       {res.get('average_cell_width', 0.0):.2f} px")
    print(f"Average cell height:      {res.get('average_cell_height', 0.0):.2f} px")
    print(f"Detection confidence:     {res.get('mean_confidence', 0.0) * 100:.1f} %")
    print(f"Preprocessing method:     {res.get('preprocess_method', 'N/A')}")
    print(f"Braille dot mode:         {res.get('dot_mode', 'N/A')}")
    print("=" * 55)


def main():
    parser = argparse.ArgumentParser(description="VisionMate Modular Braille Recognition CLI")
    parser.add_argument("--input", "-i", type=str, required=True, help="Path to input Braille photograph")
    parser.add_argument("--mode", "--dot-mode", type=str, default="auto", choices=["auto", "embossed", "printed"],
                        help="Braille dot mode: 'auto', 'embossed', or 'printed'")
    parser.add_argument("--debug", action="store_true", help="Enable debug mode saving 01-09 diagnostic artifacts")
    parser.add_argument("--debug-dir", type=str, default="debug", help="Directory to save debug artifacts")
    parser.add_argument("--preprocess", type=str, default=PREPROCESS_METHOD_COMBINED,
                        choices=[PREPROCESS_METHOD_CLAHE, PREPROCESS_METHOD_BLACKHAT, PREPROCESS_METHOD_GRADIENT, PREPROCESS_METHOD_COMBINED, PREPROCESS_METHOD_PRINTED],
                        help="Preprocessing method")
    parser.add_argument("--grade2", action="store_true", help="Use Grade 2 UEB Liblouis translation instead of Grade 1")
    parser.add_argument("--no-lm", action="store_true", help="Disable language model post-correction")
    parser.add_argument("--milestone-only", action="store_true", help="Run only up to cell grouping & visualization")
    parser.add_argument("--geometric", "--geometric-mode", action="store_true", help="Run dedicated Geometric Braille Analysis Mode (Phases 1-8)")

    args = parser.parse_args()

    if args.geometric:
        from .geometric_analysis import GeometricBrailleAnalyzer
        analyzer = GeometricBrailleAnalyzer(debug_dir=args.debug_dir)
        analyzer.run(args.input, enable_decode_bridge=not args.milestone_only)
        return

    stem = os.path.splitext(os.path.basename(args.input))[0]
    pipeline = BrailleRecognitionPipeline(
        dot_mode=args.mode,
        default_preprocess_method=args.preprocess,
        use_grade2=args.grade2,
        enable_language_correction=not args.no_lm
    )

    print(f"\nProcessing '{args.input}' with method='{args.preprocess}'...")
    res = pipeline.process(
        args.input,
        debug=args.debug,
        debug_dir=args.debug_dir,
        filename_stem=stem,
        milestone_only=args.milestone_only
    )

    print_statistics(res)

    if args.milestone_only:
        print(f"\n[MILESTONE READY] Cell visualization saved to: {res['visualization_path']}")
        return

    try:
        print("\nRAW BRAILLE DECODE:")
        print(res["raw_braille"][:500] + ("..." if len(res["raw_braille"]) > 500 else ""))
        print("\nCORRECTED TEXT:")
        print(res["corrected_text"][:500] + ("..." if len(res["corrected_text"]) > 500 else ""))
    except Exception:
        sys.stdout.buffer.write(f"\nRAW BRAILLE DECODE:\n{res['raw_braille'][:500]}\n".encode("utf-8", errors="replace"))
        sys.stdout.buffer.write(f"\nCORRECTED TEXT:\n{res['corrected_text'][:500]}\n".encode("utf-8", errors="replace"))

    print(f"\nDiagnostic cell visualization saved to: {res['visualization_path']}")


if __name__ == "__main__":
    main()
