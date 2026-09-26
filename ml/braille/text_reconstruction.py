"""
Word and Line Text Reconstruction Module.
Reconstructs formatted paragraphs, lines, and words from decoded Braille cells:
- Determines character boundaries from canonical cell positions
- Computes local spacing statistics (intra-word vs inter-word gaps)
- Reconstructs words without assuming rigid fixed thresholds
- Preserves natural line breaks and formatting
"""

import numpy as np
from typing import List, Dict, Any, Tuple
from .cell_segmentation import BrailleCellCandidate
from .braille_decoder import decode_line_grade1, decode_line_grade2_liblouis


def reconstruct_text_from_cells(
    grid_lines: List[List[BrailleCellCandidate]],
    use_grade2: bool = False,
    table: str = "en-ueb-g2.ctb"
) -> Dict[str, Any]:
    """
    Reconstructs complete multi-line text from 2x3 Braille cell lines:
    1. Analyzes local horizontal spacing between consecutive cells per line:
       Calculates median character pitch; marks word breaks where gap exceeds
       1.5 * median intra-word cell spacing.
    2. Decodes line by line using deterministic Grade 1 rules (or optional Grade 2).
    3. Preserves line breaks and computes word statistics.

    Returns:
    {
        "raw_braille": str,
        "raw_decoded_text": str,
        "lines": List[Dict[str, Any]],
        "total_words": int,
        "total_lines": int
    }
    """
    lines_info = []
    raw_braille_lines = []
    text_lines = []
    total_words = 0

    for line_idx, line in enumerate(grid_lines):
        if not line:
            continue

        # Dynamic spacing calibration across this specific line
        if len(line) >= 2:
            cxs = np.array([c.cx for c in line], dtype=np.float32)
            gaps = np.diff(cxs)
            # Filter out wide multi-word spaces to determine intra-word cell pitch
            intra_word_gaps = gaps[gaps < np.median(gaps) * 1.8]
            med_char_pitch = float(np.median(intra_word_gaps)) if len(intra_word_gaps) > 0 else float(np.median(gaps))
            word_gap_thresh = med_char_pitch * 1.55

            for i in range(len(line) - 1):
                gap = line[i+1].cx - line[i].cx
                if gap > word_gap_thresh:
                    line[i+1].has_space_before = True

        # Decode line
        if use_grade2:
            u_str, t_str = decode_line_grade2_liblouis(line, table=table)
        else:
            u_str, t_str = decode_line_grade1(line)

        raw_braille_lines.append(u_str)
        text_lines.append(t_str)

        words_in_line = len(t_str.split())
        total_words += words_in_line

        lines_info.append({
            "line_index": line_idx,
            "y": round(float(np.mean([c.cy for c in line])), 1),
            "cell_count": len(line),
            "word_count": words_in_line,
            "braille": u_str,
            "text": t_str
        })

    raw_braille_full = "\n".join(raw_braille_lines)
    raw_text_full = "\n".join(text_lines)

    return {
        "raw_braille": raw_braille_full,
        "raw_decoded_text": raw_text_full,
        "lines": lines_info,
        "total_words": total_words,
        "total_lines": len(lines_info)
    }
