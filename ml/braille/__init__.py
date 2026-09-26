"""
VisionMate Braille Recognition Engine.
Modular pipeline separating:
1. Image validation & ingestion
2. Perspective correction & page rectification
3. Illumination correction & multi-method preprocessing
4. Embossed dot detection
5. Continuous 2x3 Braille cell segmentation
6. Deterministic Grade 1 & Grade 2 Braille decoding
7. Word and line reconstruction
8. Cell visualization & error localization
"""

from .preprocessing import (
    preprocess_image,
    normalize_illumination,
    enhance_clahe,
    morphological_dipoles,
    gradient_emboss_enhancement,
    adaptive_threshold_image,
    evaluate_preprocessing_candidates,
    PREPROCESS_METHOD_CLAHE,
    PREPROCESS_METHOD_BLACKHAT,
    PREPROCESS_METHOD_GRADIENT,
    PREPROCESS_METHOD_COMBINED,
    PREPROCESS_METHOD_PRINTED,
)

from .perspective import (
    rectify_page_perspective,
    detect_page_corners,
    order_quad_points,
    normalize_orientation,
)

from .dot_detection import (
    detect_embossed_braille_dots,
    detect_printed_braille_dots,
    detect_braille_dots,
    EmbossedDotResult,
    PrintedDotResult,
)

from .cell_segmentation import (
    segment_dots_into_cells,
    estimate_pitches,
    BrailleCellCandidate,
    GRID_COORDS_TO_DOT_NUM,
    DOT_NUM_TO_GRID_COORDS,
)

from .visualization import (
    visualize_cells_and_dots,
    export_cell_diagnostics,
)

from .braille_decoder import (
    decode_cell_pattern,
    decode_line_grade1,
    pattern_to_unicode,
    unicode_to_pattern,
    BRAILLE_MAP_GRADE1,
)

from .text_reconstruction import (
    reconstruct_text_from_cells,
)

from .error_analysis import (
    analyze_cell_confidences,
    classify_recognition_errors,
)

from .pipeline import (
    BrailleRecognitionPipeline,
)

from .geometric_analysis import (
    GeometricBrailleAnalyzer,
    CellStatus,
    GeometricCell,
    GeometricDot,
    LineGeometryStats,
)

__all__ = [
    'preprocess_image',
    'normalize_illumination',
    'enhance_clahe',
    'morphological_dipoles',
    'gradient_emboss_enhancement',
    'adaptive_threshold_image',
    'evaluate_preprocessing_candidates',
    'PREPROCESS_METHOD_CLAHE',
    'PREPROCESS_METHOD_BLACKHAT',
    'PREPROCESS_METHOD_GRADIENT',
    'PREPROCESS_METHOD_COMBINED',
    'PREPROCESS_METHOD_PRINTED',
    'rectify_page_perspective',
    'detect_page_corners',
    'order_quad_points',
    'normalize_orientation',
    'detect_embossed_braille_dots',
    'detect_printed_braille_dots',
    'detect_braille_dots',
    'EmbossedDotResult',
    'PrintedDotResult',
    'segment_dots_into_cells',
    'estimate_pitches',
    'BrailleCellCandidate',
    'GRID_COORDS_TO_DOT_NUM',
    'DOT_NUM_TO_GRID_COORDS',
    'visualize_cells_and_dots',
    'export_cell_diagnostics',
    'decode_cell_pattern',
    'decode_line_grade1',
    'pattern_to_unicode',
    'unicode_to_pattern',
    'BRAILLE_MAP_GRADE1',
    'reconstruct_text_from_cells',
    'analyze_cell_confidences',
    'classify_recognition_errors',
    'BrailleRecognitionPipeline',
    'GeometricBrailleAnalyzer',
    'CellStatus',
    'GeometricCell',
    'GeometricDot',
    'LineGeometryStats',
]
