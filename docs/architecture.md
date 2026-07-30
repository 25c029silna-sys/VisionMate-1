# VisionMate Architecture

## App Layer
- `app/lib/main.dart` — application entry point.
- `app/lib/app.dart` — MaterialApp and route registration.
- `app/lib/core/` — shared services for voice, camera, permissions, storage, and TFLite.
- `app/lib/features/` — feature modules for Braille, digital library, OCR reader, scene/navigation, and emergency SOS.
- `app/lib/widgets/` — shared accessible UI components.

## Feature Modules
- `braille/` — OpenCV preprocessing, Braille segmentation, CNN inference.
- `digital_library/` — document storage, embeddings, similarity search.
- `ocr_reader/` — ML Kit text recognition and spoken reading.
- `scene_navigation/` — YOLOv8 live detection and spoken navigation.
- `emergency_sos/` — accelerometer, GPS, and SMS emergency flow.

## Data Flow
1. User issue voice command.
2. ASR interprets command and routes to a feature.
3. Feature performs local inference or sensor processing.
4. TTS confirms results to the user.

## Known Tradeoffs

### Vector Embedding Search Scalability (`digital_library`)
- **Linear Scan Overhead**: Document similarity search currently queries vector embeddings stored as serialized JSON strings in SQLite, deserializes them, and computes cosine similarity sequentially in Dart ($O(N)$ time complexity).
- **Execution Isolate**: Vector calculations currently execute on the main UI isolate.
- **Practical Ceiling**: Tested ceiling is ~500 documents on standard mobile devices. Higher document counts risk UI main-thread jank during search.
- **Mitigation & Road Map**: Scored query sets are bounded by a default candidate limit (`maxCandidates = 100`). For larger production libraries, offloading vector math to a background Dart isolate or integrating an native vector index plugin (e.g. HNSW/sqlite-vss) is recommended.

### OCR Reading-Order Assembly (`ocr_reader`)
- **Block Layout Ordering**: Google ML Kit returns raw text blocks in detection order, which may jump out of natural document order. `OcrService` applies a two-pass sorting algorithm (`sortTextBlocksInReadingOrder`):
  - **Primary Sort**: Top-to-bottom vertical ordering based on bounding box top coordinate (`boundingBox.top`).
  - **Secondary Sort**: Left-to-right horizontal ordering (`boundingBox.left`) applied when vertical block coordinates fall within a horizontal line-band threshold ($\Delta y \le 20\text{px}$).
- **Failure Resilience & Non-Blocking Context**: Empty ML Kit results emit a clean audio alert without error propagation. Optional web context expansion (`fetchWebContext`) executes non-blocking HTTP pings; network timeouts or offline status return a silent fallback without invalidating or delaying core spoken text playback.


