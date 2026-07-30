# VisionMate API Contracts

## TFLite Model Interfaces

### Braille CNN
- Input: preprocessed 28x28 grayscale Braille cell tensor.
- Output: class logits for Braille patterns.
- Asset: `assets/models/braille_cnn.tflite`
- Labels: `assets/labels/braille_labels.txt`

### YOLOv8 Obstacle Detection
- Input: camera frame tensor.
- Output: bounding boxes, scores, class ids.
- Asset: `assets/models/yolov8n.tflite`
- Labels: `assets/labels/yolo_labels.txt`

### MiniLM Embeddings
- Input: text token ids or plain text tokens.
- Output: embedding vector tensor.
- Asset: `assets/models/minilm.tflite`

## Dart Layer Contracts

- `VoiceCommandRouter` maps a spoken phrase to a feature action.
- `StorageService` persists `DocumentRecord` and `EmbeddingRecord`.
- `EmergencySosService` exposes `listenForShake()` and `sendSos()`.
- `OcrReaderService` exposes `scanImage()` and `readText()`.
