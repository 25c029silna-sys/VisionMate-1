# VisionMate Requirements Specification

## Functional Requirements

1. Braille Capture & Preprocessing
   - Photograph a Braille page.
   - Detect page edges and perform perspective correction.
   - Apply contrast, noise cleanup, and enhancement.

2. Braille Cell Segmentation & Classification
   - Segment Braille cells from the preprocessed page.
   - Classify each cell with a CNN.
   - Assemble structured text output.

3. Semantic Document Search
   - Store documents locally.
   - Generate sentence embeddings on-device with MiniLM.
   - Rank documents by cosine similarity for spoken queries.

4. OCR-Based Reading
   - Extract text via Google ML Kit from images.
   - Speak extracted text by TTS.
   - Optionally expand context with web lookup.

5. Scene Description & Indoor Navigation
   - Analyze live camera feed with YOLOv8.
   - Provide spoken obstacle alerts in near-real-time.
   - Offer on-demand scene overviews.

6. Emergency SOS
   - Detect an accelerometer shake gesture.
   - Fetch GPS coordinates.
   - Send an SMS alert to a configured emergency contact.

## Non-Functional Requirements

- Performance: support near-real-time obstacle alerts and fast Braille classification.
- Offline functionality: core models run without internet.
- Scalability: digital library search remains responsive as documents grow.
- Accuracy: Braille classification should maintain high accuracy.
- Reliability: robust to lighting, angle, and background app state.
- Usability: fully voice-operable UI.
- Maintainability: modular and upgradeable feature modules.
