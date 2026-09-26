# Embossed Braille Recognition Model & Research Archive

This directory consolidates all legacy, experimental, and research assets related to **embossed (tactile paper / shadow-dipole) Braille recognition**, separated cleanly by purpose.

> [!NOTE]
> **Active Production Pipeline Notice:**  
> The VisionMate mobile application (`app/`) and primary ML pipeline (`ml/braille/`) strictly utilize the **high-accuracy non-embossed (printed/flat/digital) Braille recognition engine** (`PrintedBrailleDetector` in pure Dart, and `detect_printed_braille_dots` in Python).  
> All files in this directory are preserved for historical reference, research, and future offline exploration without affecting the active non-embossed recognition pipeline.

---

## Directory Organization

```
embossed_braille_recognition/
├── models/                     # Trained weights, TFLite models, SavedModels
│   ├── yolov8_braille/         # YOLOv8 embossed Braille detector (PyTorch .pt, TFLite, SavedModel)
│   ├── ssd_model/              # SSD MobileNet embossed Braille model & labels
│   ├── angelina_weights/       # Pretrained weights & retina model for Angelina Braille Reader
│   └── yolov8n.pt              # Base YOLOv8 nano model checkpoint
│
├── training/                   # Model training and dataset preparation pipelines
│   ├── braille_cnn/            # 64-class Braille cell patch CNN training scripts & notebooks
│   ├── dataset_prep/           # Synthetic shadow-dipole generators & DSBI patch extractors
│   │   ├── prepare_braille_dataset.py     # Generates synthetic embossed cell images with shadow/crest
│   │   ├── prepare_dsbi_dataset.py        # Extracts cell patches from DSBI embossed dataset
│   │   ├── download_braille_dataset.py    # Downloads DSBI dataset & Angelina weights
│   │   └── export_yolov8_braille_tflite.py# Exports YOLOv8 model to optimized TFLite FlatBuffer
│   └── angelina_training/      # Neural network training modules from Angelina Reader
│
├── testing/                    # Comprehensive testing suites, validation, and experiments
│   ├── unit_tests/             # Unit tests for embossed dot algorithms
│   │   ├── test_braille_modular.py        # Highlight-shadow dipole pairing tests
│   │   ├── test_braille_ocr_pipeline.py   # Full embossed OCR pipeline tests
│   │   ├── test_braille_grid_liblouis.py  # 2x3 grid fitting & Liblouis Grade 2 decoding
│   │   └── test_geometric_analysis.py     # Geometric embossed cell analysis
│   ├── yolo_validation/        # YOLOv8 embossed model validation scripts & benchmark images
│   │   ├── auto_orient_test.py, compare_thresholds.py, inspect_details.py
│   │   ├── test_letterbox.py, test_refiner.py, verify_yolo.py, etc.
│   │   └── Benchmark test images (.jpg/.jpeg)
│   ├── cnn_validation/         # CNN evaluation scripts and training accuracy curves
│   └── experiments/            # Scratch prototyping scripts & debug visualization artifacts
│       ├── test_adaptive_dots.py, test_continuous_lattice.py, test_full_overhaul.py
│       └── artifacts/          # Generated debug overlays, dot masks, and calibration data
│
└── pipelines/                  # End-to-end embossed recognition pipeline implementations
    ├── braille_ocr/            # White-on-white shadow-dipole OCR pipeline with Liblouis
    └── angelina_reader/        # Angelina Braille Reader web app and inference engine
```

---

## Component Details

### 1. Models (`models/`)
- **YOLOv8 Braille Detector (`models/yolov8_braille/`)**:
  - `yolov8_braille.pt`: PyTorch weights trained on embossed Braille pages.
  - `yolov8_braille.tflite`: Quantized TensorFlow Lite FlatBuffer for mobile CPU execution.
  - `yolov8_braille_saved_model/`: TensorFlow SavedModel format directory.
- **SSD Model (`models/ssd_model/`)**:
  - `labelmap.txt`: 64-class mapping for Braille cell combinations.
  - `ssd.zip`: Archived MobileNet SSD model checkpoints.
- **Angelina Weights (`models/angelina_weights/`)**:
  - Pretrained retina model weights (`model.t7` / `weights/`) for double-sided embossed page recognition.

### 2. Training (`training/`)
- **CNN Training (`training/braille_cnn/`)**:
  - `train.py`: Trains a lightweight CNN on 28x28 grayscale Braille cell crops across 64 classes.
  - `preprocess.py`: Normalizes and augments cell patches.
  - `export_tflite.py`: Exports trained Keras models to TFLite format.
- **Dataset Preparation (`training/dataset_prep/`)**:
  - `prepare_braille_dataset.py`: Synthetically generates 6-dot Braille cells by simulating realistic directional shadows (troughs) and specular crests.
  - `prepare_dsbi_dataset.py`: Parses Double-Sided Braille Image (DSBI) annotations and slices cell patches.

### 3. Testing & Validation (`testing/`)
- **Unit Tests (`testing/unit_tests/`)**:
  - Validates shadow-dipole pairing, morphological filtering (Top-Hat / Black-Hat), continuous lattice fitting, and orientation detection.
- **YOLO Validation (`testing/yolo_validation/`)**:
  - Scripts testing letterbox resizing, orientation invariance (0°, 90°, 180°, 270°), gap multipliers, and word boundary reconstruction against real smartphone photos.
- **Experiments (`testing/experiments/`)**:
  - Experimental phase-locking, adaptive dot segmentation, and lattice regression algorithms developed during embossed paper research.

### 4. Pipelines (`pipelines/`)
- **Braille OCR Engine (`pipelines/braille_ocr/`)**:
  - `pipeline.py`: Main `BrailleOCRPipeline` orchestrating perspective warp, orientation detection, dot segmentation, and beam-search language model decoding.
  - `dot_segmenter.py`: White-on-white embossed dot detection using paired highlight-shadow dipoles and rigid lattice fitting.
  - `grade2_decoder.py`: Liblouis C-API wrapper for Unified English Braille (UEB) Grade 2 contracted translation.
- **Angelina Reader (`pipelines/angelina_reader/`)**:
  - Standalone web and CLI system for double-sided embossed page recognition developed by Ilya Ovodov.

---

## Active Non-Embossed Pipeline Verification

The active non-embossed recognition capability remains housed within:
- **Mobile Engine**: [app/lib/features/braille/domain/printed_braille_detector.dart](file:///c:/Users/Vijil/OneDrive/Documents/GitHub/VisionMate-1/app/lib/features/braille/domain/printed_braille_detector.dart)
- **Service Integration**: [app/lib/features/braille/domain/braille_service.dart](file:///c:/Users/Vijil/OneDrive/Documents/GitHub/VisionMate-1/app/lib/features/braille/domain/braille_service.dart)
- **Python ML Reference**: [ml/braille/dot_detection.py](file:///c:/Users/Vijil/OneDrive/Documents/GitHub/VisionMate-1/ml/braille/dot_detection.py) and [ml/tests/test_printed_braille.py](file:///c:/Users/Vijil/OneDrive/Documents/GitHub/VisionMate-1/ml/tests/test_printed_braille.py)
- **Interactive Demo**: [scripts/demo_printed_braille.py](file:///c:/Users/Vijil/OneDrive/Documents/GitHub/VisionMate-1/scripts/demo_printed_braille.py)
