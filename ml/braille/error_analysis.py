"""
Confidence and Error Localization Module.
Provides structured diagnostic telemetry:
- Records per-cell confidence and 6-dot activation confidences
- Flags ambiguous cell patterns (marginal contrast, pitch outliers)
- Classifies root causes of recognition discrepancies into:
  A. Dot detection error
  B. Cell segmentation error
  C. Braille pattern decoding error
  D. Text reconstruction error
  E. Language correction error
"""

from typing import List, Dict, Any, Optional, Tuple
from .cell_segmentation import BrailleCellCandidate
from .braille_decoder import decode_cell_pattern, BRAILLE_MAP_GRADE1


def analyze_cell_confidences(
    grid_lines: List[List[BrailleCellCandidate]]
) -> Dict[str, Any]:
    """
    Evaluates confidence metrics across all detected cells:
    - Identifies ambiguous patterns (confidence < 0.60 or invalid Braille configurations)
    - Records detailed per-cell metadata.
    """
    total_cells = 0
    low_confidence_cells = []
    unmapped_cells = []
    cell_records = []

    confs = []

    for line in grid_lines:
        for cell in line:
            total_cells += 1
            confs.append(cell.confidence)
            pattern_tup = tuple(cell.dots)

            char, _, _ = decode_cell_pattern(cell.dots)
            is_valid = pattern_tup in BRAILLE_MAP_GRADE1 or sum(pattern_tup) == 0

            record = {
                "cell_index": cell.cell_index,
                "line_index": cell.line_index,
                "pattern": cell.dots,
                "binary_str": cell.binary_str,
                "character": char,
                "confidence": round(cell.confidence, 4),
                "dot_confidences": [round(c, 4) for c in cell.dot_confidences],
                "is_ambiguous": cell.confidence < 0.60 or not is_valid
            }
            cell_records.append(record)

            if cell.confidence < 0.60:
                low_confidence_cells.append(record)
            if not is_valid:
                unmapped_cells.append(record)

    mean_conf = float(np.mean(confs)) if confs else 0.0

    return {
        "total_cells": total_cells,
        "mean_confidence": round(mean_conf, 4),
        "low_confidence_count": len(low_confidence_cells),
        "unmapped_pattern_count": len(unmapped_cells),
        "cell_records": cell_records,
        "ambiguous_cells": low_confidence_cells + unmapped_cells
    }


def classify_recognition_errors(
    expected_text: str,
    recognized_cells: List[BrailleCellCandidate],
    raw_decoded_text: str,
    corrected_text: Optional[str] = None
) -> List[Dict[str, Any]]:
    """
    Localizes and classifies discrepancies between expected text and pipeline output:
    Categories:
    - 'dot_detection_error': Expected dot missing or false positive dot detected in cell
    - 'cell_segmentation_error': Cell boundary misaligned or phase offset
    - 'braille_decoding_error': Pattern present but mapped incorrectly
    - 'text_reconstruction_error': Word space inserted or missing
    - 'language_correction_error': Raw decode was closer to expected than post-correction
    """
    diagnostics = []

    exp_words = expected_text.split()
    rec_words = raw_decoded_text.split()
    corr_words = corrected_text.split() if corrected_text else rec_words

    for i in range(min(len(exp_words), len(rec_words))):
        exp_w = exp_words[i]
        rec_w = rec_words[i]
        corr_w = corr_words[i] if i < len(corr_words) else ""

        if exp_w.lower() != rec_w.lower():
            # Error detected in this word
            error_type = "dot_detection_error"
            detail = f"Word mismatch: expected '{exp_w}', raw decoded '{rec_w}'"

            # Check if length matches (indicates single-cell dot slip)
            if len(exp_w) == len(rec_w):
                error_type = "dot_detection_error"
                detail += " (1-to-1 letter substitution, likely 1-dot drop or false highlight)"
            elif abs(len(exp_w) - len(rec_w)) > 1:
                error_type = "cell_segmentation_error"
                detail += " (Length disparity, likely phase drift or missing cell)"

            # Check if language model introduced or fixed the error
            if corr_w.lower() == exp_w.lower():
                detail += f" -> Successfully resolved by language correction to '{corr_w}'"
            elif corr_w and corr_w.lower() != exp_w.lower() and corr_w.lower() != rec_w.lower():
                error_type = "language_correction_error"
                detail += f" -> Over-corrected by language model to '{corr_w}'"

            diagnostics.append({
                "word_index": i,
                "expected": exp_w,
                "recognized": rec_w,
                "corrected": corr_w,
                "error_type": error_type,
                "detail": detail
            })

    return diagnostics


import numpy as np
