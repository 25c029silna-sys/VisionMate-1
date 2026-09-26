"""
VisionMate Braille Optical Character Recognition (OCR) Engine
Package containing preprocessing, dot segmentation, rigid lattice grid fitting, Grade 2 Liblouis decoding, and end-to-end pipeline.
"""

from .preprocessor import (
    detect_page_contour,
    warp_perspective,
    detect_orientation,
    score_braille_distribution,
    analyze_shadow_gradient,
)
from .dot_segmenter import (
    detect_embossed_dots,
    estimate_global_pitches,
    detect_line_baselines,
    fit_continuous_line_lattice,
    fit_braille_grid,
    export_grid_debug_image,
    snap_yolo_detections_to_lattice,
    BrailleGridCell,
    EmbossedDot,
    GRID_COORDINATE_TO_DOT_NUMBER,
    grid_coords_to_dot_number,
    grid_coords_to_dot_index,
)
from .grade2_decoder import (
    Grade2BrailleDecoder,
    LiblouisGrade2Decoder,
    BeamSearchDecoder,
    dots_to_unicode,
    binary_str_to_unicode,
)
from .pipeline import (
    BrailleOCRPipeline,
)
from . import louis

__all__ = [
    'detect_page_contour',
    'warp_perspective',
    'detect_orientation',
    'score_braille_distribution',
    'analyze_shadow_gradient',
    'detect_embossed_dots',
    'estimate_global_pitches',
    'detect_line_baselines',
    'fit_continuous_line_lattice',
    'fit_braille_grid',
    'export_grid_debug_image',
    'snap_yolo_detections_to_lattice',
    'BrailleGridCell',
    'EmbossedDot',
    'GRID_COORDINATE_TO_DOT_NUMBER',
    'grid_coords_to_dot_number',
    'grid_coords_to_dot_index',
    'Grade2BrailleDecoder',
    'LiblouisGrade2Decoder',
    'BeamSearchDecoder',
    'dots_to_unicode',
    'binary_str_to_unicode',
    'BrailleOCRPipeline',
    'louis',
]
