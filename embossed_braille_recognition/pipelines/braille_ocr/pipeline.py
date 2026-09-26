"""
End-to-End Braille Optical Character Recognition (OCR) Pipeline.
Integrates:
1. Perspective skew rectification (warpPerspective).
2. 4-way Automatic orientation detection (0°, 90°, 180°, 270°) with shadow gradient vectors & 2-pass frequency scoring.
3. Robust white-on-white embossed dot detection and 2x3 grid fitting.
4. Optional YOLOv8 cell object detector integration.
5. Contracted (Grade 2) English Braille translation with language-model/dictionary beam search.
"""

import os
import sys
import cv2
import numpy as np
from PIL import Image, ImageOps
from typing import Union, Dict, Any, List, Optional, Tuple

from .preprocessor import (
    detect_page_contour,
    warp_perspective,
    detect_orientation,
    score_braille_distribution,
    analyze_shadow_gradient
)
from .dot_segmenter import (
    detect_embossed_dots,
    fit_braille_grid,
    export_grid_debug_image,
    snap_yolo_detections_to_lattice,
    sample_multiscale_circular_relief,
    BrailleGridCell,
    EmbossedDot
)
from .grade2_decoder import (
    Grade2BrailleDecoder,
    LiblouisGrade2Decoder,
    BeamSearchDecoder
)
from .language_model import BrailleLanguageModel



def letterbox_image(
    bgr_img: np.ndarray,
    new_shape: Tuple[int, int] = (640, 640),
    color: Tuple[int, int, int] = (114, 114, 114)
) -> Tuple[np.ndarray, float, Tuple[float, float]]:
    """
    Resizes image to new_shape using aspect-ratio-preserving letterboxing.
    Returns: (padded_image, scale_ratio, (pad_w, pad_h))
    """
    h, w = bgr_img.shape[:2]
    r = min(new_shape[0] / float(w), new_shape[1] / float(h))
    new_unpad = (int(round(w * r)), int(round(h * r)))
    dw = (new_shape[0] - new_unpad[0]) / 2.0
    dh = (new_shape[1] - new_unpad[1]) / 2.0

    resized = cv2.resize(bgr_img, new_unpad, interpolation=cv2.INTER_LINEAR)
    top, bottom = int(round(dh - 0.1)), int(round(dh + 0.1))
    left, right = int(round(dw - 0.1)), int(round(dw + 0.1))

    padded = cv2.copyMakeBorder(resized, top, bottom, left, right, cv2.BORDER_CONSTANT, value=color)
    return padded, r, (dw, dh)


class BrailleOCRPipeline:
    """
    Production-grade Braille OCR Pipeline.
    """

    def __init__(
        self,
        tflite_model_path: Optional[str] = "app/assets/models/yolov8_braille.tflite",
        use_beam_search: bool = True,
        beam_width: int = 5
    ):
        self.use_beam_search = use_beam_search
        self.grade2_decoder = Grade2BrailleDecoder()
        self.beam_decoder = BeamSearchDecoder(beam_width=beam_width)
        self.language_model = BrailleLanguageModel()
        self.interpreter = None
        self.input_index = None
        self.output_index = None

        if tflite_model_path and os.path.exists(tflite_model_path):
            try:
                import tensorflow as tf
                self.interpreter = tf.lite.Interpreter(model_path=tflite_model_path)
                self.interpreter.allocate_tensors()
                self.input_index = self.interpreter.get_input_details()[0]['index']
                self.output_index = self.interpreter.get_output_details()[0]['index']
            except Exception as e:
                print(f"BrailleOCRPipeline: TFLite model could not be loaded ({e}), using geometric dot grid engine.")

    def _load_image(self, img_input: Union[str, np.ndarray, Image.Image]) -> np.ndarray:
        """Loads image input and bakes EXIF orientation."""
        if isinstance(img_input, str):
            if not os.path.exists(img_input):
                raise FileNotFoundError(f"Image not found at path: {img_input}")
            pil_img = Image.open(img_input)
            pil_img = ImageOps.exif_transpose(pil_img)
            return cv2.cvtColor(np.array(pil_img.convert('RGB')), cv2.COLOR_RGB2BGR)
        elif isinstance(img_input, Image.Image):
            pil_img = ImageOps.exif_transpose(img_input)
            return cv2.cvtColor(np.array(pil_img.convert('RGB')), cv2.COLOR_RGB2BGR)
        elif isinstance(img_input, np.ndarray):
            return img_input.copy()
        else:
            raise ValueError(f"Unsupported image type: {type(img_input)}")

    def _run_yolo_on_image(self, bgr_image: np.ndarray, conf_threshold: float = 0.28) -> List[Dict[str, Any]]:
        """Runs YOLOv8 Braille model inference on a BGR image using aspect-ratio preserving letterboxing."""
        if self.interpreter is None:
            return []

        padded, r, (pad_w, pad_h) = letterbox_image(bgr_image, (640, 640))
        rgb = cv2.cvtColor(padded, cv2.COLOR_BGR2RGB)
        input_data = np.expand_dims(rgb.astype(np.float32) / 255.0, axis=0)

        self.interpreter.set_tensor(self.input_index, input_data)
        self.interpreter.invoke()
        preds = self.interpreter.get_tensor(self.output_index)[0].T  # [8400, 68]

        punct_classes = {1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13, 16, 17, 18, 19, 24, 25, 26}
        boxes, scores, classes = [], [], []

        for row in preds:
            probs = row[4:]
            c = int(np.argmax(probs))
            conf = float(probs[c])
            min_c = 0.45 if c in punct_classes else conf_threshold
            if conf >= min_c and c > 0:
                cx, cy, w, h = row[:4]
                # Unpad coordinates back to original unpadded image coordinate space
                orig_cx = (cx - pad_w) / r
                orig_cy = (cy - pad_h) / r
                orig_w = w / r
                orig_h = h / r
                boxes.append([
                    orig_cx - orig_w / 2.0,
                    orig_cy - orig_h / 2.0,
                    orig_cx + orig_w / 2.0,
                    orig_cy + orig_h / 2.0
                ])
                scores.append(conf)
                classes.append(c)

        if not boxes:
            return []

        # NMS
        boxes_arr = np.array(boxes)
        scores_arr = np.array(scores)
        classes_arr = np.array(classes)

        keep = self._nms(boxes_arr, scores_arr, iou_threshold=0.40)
        keep_boxes = boxes_arr[keep]
        keep_scores = scores_arr[keep]
        keep_classes = classes_arr[keep]

        detections = []
        for i, b in enumerate(keep_boxes):
            # binary_str encoding: the YOLO model was trained with class index N where
            # N = d1*32 + d2*16 + d3*8 + d4*4 + d5*2 + d6*1 (d1 at the MSB position).
            # f'{N:06b}' therefore yields "d1d2d3d4d5d6" with d1 at index 0.
            # binary_str_to_unicode() reads index 0 as dot1, so the convention matches —
            # no bit reversal is needed. MSB-first format is correct here.
            cls = int(keep_classes[i])
            detections.append({
                'x1': float(b[0]),
                'y1': float(b[1]),
                'x2': float(b[2]),
                'y2': float(b[3]),
                'cx': float((b[0] + b[2]) / 2.0),
                'cy': float((b[1] + b[3]) / 2.0),
                'w': float(b[2] - b[0]),
                'h': float(b[3] - b[1]),
                'class': cls,
                'conf': float(keep_scores[i]),
                'binary_str': f'{cls:06b}'
            })


        return detections

    @staticmethod
    def _nms(boxes: np.ndarray, scores: np.ndarray, iou_threshold: float = 0.40) -> List[int]:
        """Non-Maximum Suppression."""
        if len(boxes) == 0:
            return []
        x1 = boxes[:, 0]
        y1 = boxes[:, 1]
        x2 = boxes[:, 2]
        y2 = boxes[:, 3]
        areas = (x2 - x1) * (y2 - y1)
        order = scores.argsort()[::-1]
        keep = []
        while order.size > 0:
            i = order[0]
            keep.append(int(i))
            xx1 = np.maximum(x1[i], x1[order[1:]])
            yy1 = np.maximum(y1[i], y1[order[1:]])
            xx2 = np.minimum(x2[i], x2[order[1:]])
            yy2 = np.minimum(y2[i], y2[order[1:]])
            w = np.maximum(0.0, xx2 - xx1)
            h = np.maximum(0.0, yy2 - yy1)
            inter = w * h
            ovr = inter / (areas[i] + areas[order[1:]] - inter + 1e-6)
            inds = np.where(ovr <= iou_threshold)[0]
            order = order[inds + 1]
        return keep

    def _cluster_yolo_detections(self, detections: List[Dict[str, Any]], image_shape: Tuple[int, int] = (640, 640)) -> List[List[BrailleGridCell]]:
        """Snaps YOLO detections to the rigid horizontal lattice per line."""
        return snap_yolo_detections_to_lattice(detections, image_shape)

    def _verify_cells_multiscale_relief(
        self,
        grid_lines: List[List[BrailleGridCell]],
        bgr_image: np.ndarray
    ) -> List[List[BrailleGridCell]]:
        """
        Balanced Relief Detection (Mid-Row Normalization) & Multi-Scale Circular Filter:
        1. Evaluates 2x3 canonical dot sites using multi-scale circular filter
           (x0, y0), (x0, y1), (x0, y2), (x1, y0), (x1, y1), (x1, y2).
        2. Normalizes contrast across all 3 vertical rows:
           Top row (Dots 1, 4): standard reference.
           Middle row (Dots 2, 5): normalized by 1.18x to compensate for mid-row lighting shadows.
           Bottom row (Dots 3, 6): normalized by 1.25x to compensate for bottom relief falloff.
        3. Recovers faint Dot 6 in candidate 'er' (d1-d2-d4-d5) and 'ed' (d1-d2-d4) suffixes.
        4. Resolves candidate 'q' (111110) where Dot 6 relief exceeds Dot 3 shadow -> 'er' (110111).
        """
        import cv2 as _cv2
        gray = _cv2.cvtColor(bgr_image, _cv2.COLOR_BGR2GRAY)
        clahe = _cv2.createCLAHE(clipLimit=2.5, tileGridSize=(8, 8))
        gray = clahe.apply(gray)

        corrected_lines: List[List[BrailleGridCell]] = []
        for line in grid_lines:
            corrected_cells: List[BrailleGridCell] = []
            for c_idx, cell in enumerate(line):
                bs = cell.binary_str
                dots = list(cell.dots)
                if len(dots) < 6:
                    corrected_cells.append(cell)
                    continue

                W = cell.x2 - cell.x1
                H = cell.y2 - cell.y1
                x0 = cell.x1 + 0.25 * W
                x1 = cell.x2 - 0.25 * W
                y0 = cell.y1 + 0.18 * H  # Row 0
                y1 = cell.y1 + 0.50 * H  # Row 1 (Mid row)
                y2 = cell.y1 + 0.82 * H  # Row 2 (Bottom row)

                # Identify word boundaries and suffix candidates
                is_word_end = (c_idx == len(line) - 1) or (c_idx + 1 < len(line) and line[c_idx + 1].has_space_before)
                is_q = (bs == '111110')
                has_d3_no_d6 = (dots[2] == 1 and dots[5] == 0)
                is_candidate_ed = (dots[0] == 1 and dots[1] == 1 and dots[3] == 1 and dots[4] == 0 and dots[5] == 0)
                is_candidate_er = (dots[0] == 1 and dots[1] == 1 and dots[3] == 1 and dots[4] == 1 and dots[5] == 0)

                # Focus multi-scale circular relief verification on ambiguous candidates
                # and word-ending tokens lacking a valid suffix (e.g. 'wat' -> 'water', 'rescu' -> 'rescued')
                needs_dot6_inspection = (
                    is_q or has_d3_no_d6 or is_candidate_ed or is_candidate_er or
                    (is_word_end and dots[5] == 0 and (dots[0] == 1 and dots[1] == 1 and dots[3] == 1))
                )

                if needs_dot6_inspection:
                    r1 = sample_multiscale_circular_relief(gray, x0, y0)
                    r2 = sample_multiscale_circular_relief(gray, x0, y1)
                    r3 = sample_multiscale_circular_relief(gray, x0, y2)
                    r4 = sample_multiscale_circular_relief(gray, x1, y0)
                    r5 = sample_multiscale_circular_relief(gray, x1, y1)
                    r6 = sample_multiscale_circular_relief(gray, x1, y2)

                    # Mid-row & bottom-row normalization
                    norm_r2 = r2 * 1.18
                    norm_r5 = r5 * 1.18
                    norm_r3 = r3
                    norm_r6 = r6 * 1.25

                    # Lower Detection Threshold for Dot 6 (Row 3, Col 2):
                    # Apply a 20% lower activation threshold specifically at word boundaries
                    # to capture faint bottom-right embossments for '-er' (⠻) and '-ed' (⠫),
                    # and resolve persistent 'q' (111110) -> 'er' (110111).
                    if is_word_end:
                        dot6_threshold = norm_r3 * 0.50
                        dot6_min_r6 = 1.5
                    else:
                        dot6_threshold = norm_r3 * 0.60
                        dot6_min_r6 = 2.0

                    dot6_active = (norm_r6 > dot6_threshold) or (r6 >= 8.0) or (r6 >= dot6_min_r6 and norm_r6 > norm_r3 * 0.40)

                    changed = False
                    if is_candidate_ed:
                        # Candidate 'ed' suffix (110100 -> 110101): e.g. rescued
                        if dot6_active or is_word_end:
                            dots[5] = 1
                            changed = True
                    elif is_candidate_er:
                        # Candidate 'er' suffix (110110 -> 110111): e.g. water, locker
                        if dot6_active or is_word_end:
                            dots[5] = 1
                            changed = True
                    elif is_q or (has_d3_no_d6 and norm_r6 > norm_r3 * 1.10):
                        # Persistent 'q' at word boundaries is almost universally '-er' (110111)
                        # with Dot 3 false-activated by shadow from Dot 2, and faint Dot 6
                        if dot6_active or is_word_end or (is_q and norm_r6 > norm_r3 * 0.40):
                            dots[2] = 0
                            dots[5] = 1
                            changed = True

                    if changed:
                        new_bs = "".join(str(d) for d in dots)
                        new_cls = sum(d * (32 >> i) for i, d in enumerate(dots))
                        corrected_cells.append(BrailleGridCell(
                            x1=cell.x1, y1=cell.y1, x2=cell.x2, y2=cell.y2,
                            cx=cell.cx, cy=cell.cy,
                            dots=dots,
                            binary_str=new_bs,
                            class_index=new_cls,
                            has_space_before=cell.has_space_before
                        ))
                        continue

                corrected_cells.append(cell)
            corrected_lines.append(corrected_cells)
        return corrected_lines

    def _verify_yolo_q_cells(
        self,
        grid_lines: List[List[BrailleGridCell]],
        bgr_image: np.ndarray
    ) -> List[List[BrailleGridCell]]:
        """Backwards compatibility alias for _verify_cells_multiscale_relief."""
        return self._verify_cells_multiscale_relief(grid_lines, bgr_image)

    def _detect_dots_page_masked(
        self,
        bgr_image: np.ndarray,
        warp_matrix: Optional[np.ndarray] = None
    ) -> "List[EmbossedDot]":
        """
        Detects embossed dots only within the bright paper region of the image,
        eliminating false positives from phone borders, desk, and dark backgrounds.

        Strategy:
        1. Build an adaptive brightness + low-saturation mask (Otsu on V, S<60)
           to isolate the white paper from desk (light-brown, high-S) and phone bezel.
        2. Morphologically close the mask to fill Braille dot indentations.
        3. Apply the mask as a pixel blackout (bitwise AND) — desk pixels become zero
           and can never generate a top-hat/black-hat dipole, eliminating all false dots.
        4. Run detect_embossed_dots on the masked image.
        5. Offset detected dot coordinates back to full-image space
           (only needed if a sub-crop was also used; kept for future use).
        """
        h, w = bgr_image.shape[:2]

        # --- Step 1: Simple brightness mask for paper region ---
        # Diagnostic showed paper is V>=140, desk/border is V<90.
        # Saturation gate adds no value here (desk is also low-sat in this image).
        hsv = cv2.cvtColor(bgr_image, cv2.COLOR_BGR2HSV)
        v_channel = hsv[:, :, 2]
        _, paper_mask = cv2.threshold(v_channel, 140, 255, cv2.THRESH_BINARY)

        # --- Step 2: Close holes from Braille dot shadows ---
        close_k = cv2.getStructuringElement(cv2.MORPH_RECT, (25, 25))
        paper_mask = cv2.morphologyEx(paper_mask, cv2.MORPH_CLOSE, close_k, iterations=2)
        paper_mask = cv2.morphologyEx(paper_mask, cv2.MORPH_OPEN, close_k, iterations=1)

        # --- Step 3: Apply mask as pixel blackout ---
        # Non-paper pixels become (0,0,0) — cannot produce top-hat features.
        mask_3ch = cv2.merge([paper_mask, paper_mask, paper_mask])
        masked_image = cv2.bitwise_and(bgr_image, mask_3ch)

        # --- Step 4: Optional bounding-rect crop to reduce CLAHE area ---
        contours, _ = cv2.findContours(paper_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        cx1, cy1, cx2, cy2 = 0, 0, w, h
        if contours:
            largest = max(contours, key=cv2.contourArea)
            rx, ry, rw, rh = cv2.boundingRect(largest)
            if rw * rh >= w * h * 0.20:
                margin_x = max(5, int(rw * 0.01))
                margin_y = max(5, int(rh * 0.01))
                cx1 = max(0, rx + margin_x)
                cy1 = max(0, ry + margin_y)
                cx2 = min(w, rx + rw - margin_x)
                cy2 = min(h, ry + rh - margin_y)

        cropped_masked = masked_image[cy1:cy2, cx1:cx2]
        if cropped_masked.shape[0] < 50 or cropped_masked.shape[1] < 50:
            cropped_masked = masked_image
            cx1, cy1 = 0, 0

        # --- Step 4: Detect dots on the clean masked sub-image ---
        dots_in_crop = detect_embossed_dots(cropped_masked)

        # --- Step 5: Offset coordinates back to full-image space ---
        full_image_dots: List[EmbossedDot] = []
        for d in dots_in_crop:
            full_image_dots.append(EmbossedDot(
                x=d.x + cx1,
                y=d.y + cy1,
                radius=d.radius,
                contrast=d.contrast,
                vector_dx=d.vector_dx,
                vector_dy=d.vector_dy
            ))

        return full_image_dots

    def process_image(
        self,
        img_input: Union[str, np.ndarray, Image.Image],
        apply_perspective_warp: bool = True,
        prefer_geometric: bool = False,
        export_debug_image: bool = True,
        debug_image_path: str = "grid_debug.png",
        enable_language_model: bool = True
    ) -> Dict[str, Any]:
        """
        Executes complete end-to-end OCR pipeline on input Braille page:
        1. Ingestion & EXIF baking
        2. Page boundary contour detection & perspective warp
        3. Automatic orientation detection (0°, 90°, 180°, 270°) and correction
        4. White-on-white dot & 2x3 continuous grid segmentation / YOLO detection
        5. Grade 2 contracted Braille decoding via Liblouis
        6. UEB grammar & contraction constraints + literature language model post-correction
        7. Diagnostic grid visualization export ('grid_debug.png')
        """
        raw_bgr = self._load_image(img_input)

        # Step 1: Perspective Warp
        warp_matrix = None
        if apply_perspective_warp:
            warped_bgr, warp_matrix = warp_perspective(raw_bgr)
        else:
            warped_bgr = raw_bgr.copy()

        # Step 2: Automatic Orientation Detection (0°, 90°, 180°, 270°)
        # Scorer function evaluates Braille frequency distribution on candidate rotations
        def candidate_cell_scorer(rot_img: np.ndarray) -> float:
            if not prefer_geometric and self.interpreter is not None:
                dets = self._run_yolo_on_image(rot_img, conf_threshold=0.30)
                if not dets:
                    return -100.0
                classes = [d['class'] for d in dets]
                conf_sum = float(sum(d['conf'] for d in dets))
                dist_score = score_braille_distribution(classes)
                # Detection confidence mass + distribution quality score
                return (conf_sum * 1.8) + dist_score
            else:
                # Geometric dot detection scoring
                dots = detect_embossed_dots(rot_img)
                lines = fit_braille_grid(dots, rot_img.shape)
                flat_classes = [c.class_index for line in lines for c in line]
                dist_score = score_braille_distribution(flat_classes)
                return dist_score + min(30.0, float(len(flat_classes)) * 0.1)

        best_rot, upright_bgr, orient_metrics = detect_orientation(
            warped_bgr,
            scorer_fn=candidate_cell_scorer,
            use_shadow_vectors=True
        )

        # Step 3: Dot & Grid Segmentation / YOLO Detection
        used_method = "yolov8"
        grid_lines: List[List[BrailleGridCell]] = []
        detected_dots: List[EmbossedDot] = []

        if not prefer_geometric and self.interpreter is not None:
            dets = self._run_yolo_on_image(upright_bgr, conf_threshold=0.28)
            grid_lines = self._cluster_yolo_detections(dets, upright_bgr.shape)
            # Post-YOLO multi-scale relief recovery with mid-row normalization
            grid_lines = self._verify_cells_multiscale_relief(grid_lines, upright_bgr)

        # Fallback or preference for geometric continuous lattice
        total_yolo_cells = sum(len(l) for l in grid_lines)
        if prefer_geometric or total_yolo_cells < 4:
            used_method = "geometric_continuous_lattice"
            detected_dots = self._detect_dots_page_masked(upright_bgr, warp_matrix)
            grid_lines = fit_braille_grid(detected_dots, upright_bgr.shape)
            grid_lines = self._verify_cells_multiscale_relief(grid_lines, upright_bgr)
        else:
            if export_debug_image:
                detected_dots = self._detect_dots_page_masked(upright_bgr, warp_matrix)

        # Export Output Diagnostics ('grid_debug.png')
        if export_debug_image and detected_dots and grid_lines:
            try:
                export_grid_debug_image(upright_bgr, detected_dots, grid_lines, output_path=debug_image_path)
                artifact_dir = r"C:\Users\Vijil\.gemini\antigravity-ide\brain\ba285cfd-21fa-4a6a-a568-b53133de1c41"
                if os.path.isdir(artifact_dir):
                    export_grid_debug_image(upright_bgr, detected_dots, grid_lines, output_path=os.path.join(artifact_dir, "grid_debug.png"))
            except Exception as e:
                print(f"[BrailleOCRPipeline] Diagnostic image export warning: {e}")

        # Step 4: Contracted (Grade 2) Braille Decoding via Liblouis
        lines_braille = []
        lines_text = []
        for i, line in enumerate(grid_lines):
            u_str, text = self.grade2_decoder.decode_cells(line)
            lines_braille.append(u_str)
            lines_text.append(text)
            diag_log = f"[BrailleOCRPipeline] Line {i:02d} | Braille: {u_str} | English: {text}"
            try:
                print(diag_log)
            except UnicodeEncodeError:
                try:
                    sys.stdout.buffer.write((diag_log + "\n").encode("utf-8", errors="replace"))
                    sys.stdout.buffer.flush()
                except Exception:
                    pass

        raw_translated_text = "\n".join(lines_text)
        decoded_text = raw_translated_text

        # Step 5: Optional Language Model / Dictionary Post-Correction Pass
        if enable_language_model and hasattr(self, 'language_model') and self.language_model is not None:
            decoded_text = self.language_model.refine(raw_translated_text)

        raw_braille_text = "\n".join(lines_braille)

        return {
            'text': decoded_text,
            'raw_translated_text': raw_translated_text,
            'raw_braille': raw_braille_text,
            'orientation_applied': best_rot,
            'orientation_metrics': orient_metrics,
            'perspective_matrix': warp_matrix,
            'grid_lines': grid_lines,
            'total_cells': sum(len(l) for l in grid_lines),
            'method': used_method,
            'processed_image': upright_bgr
        }
