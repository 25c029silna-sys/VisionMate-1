# VisionMate ML Workspace

This workspace contains stubbed training and export scripts for VisionMate's on-device models.

## Directories
- `braille_cnn/` — Braille cell classification training and export.
- `yolov8_obstacle/` — YOLOv8 obstacle detection training and export.
- `minilm_embeddings/` — MiniLM embedding export to TensorFlow Lite.

## Setup

1. Create a virtual environment:
   ```bash
   python -m venv .venv
   source .venv/bin/activate
   ```
2. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

## Notes

- These scripts are intentionally stubbed with TODOs for dataset paths, architecture tuning, and export details.
- Replace placeholder logic with real training data and model export once the dataset is available.
