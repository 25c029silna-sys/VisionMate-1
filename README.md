# VisionMate

VisionMate is a voice-guided Android application for blind and visually impaired users. It integrates offline-first AI assistive technologies into one platform: Braille recognition, semantic search, OCR reading, scene description, indoor navigation, and emergency SOS.

## Project Structure

- `app/` — Flutter Android application
- `ml/` — Python model training workspace
- `docs/` — architecture, requirements, and API contracts
- `.github/workflows/` — CI workflows for Flutter and Python

## Setup

### Flutter App
1. Install Flutter and Android tooling.
2. Open `e:\VisonMate\app`.
3. Run `flutter pub get`.
4. Run `flutter build apk --debug`.

### Python Workspace
1. Create and activate a Python virtual environment.
2. Install dependencies: `pip install -r e:\VisonMate\ml\requirements.txt`.

## Swapping Models

Replace model stubs in `app/assets/models/` with trained `.tflite` files. Update label files in `app/assets/labels/` as needed.

## Notes

- All core AI inference is designed for on-device TensorFlow Lite execution.
- The UX is voice-first: every action is triggered by speech commands and confirmed with TTS.
- OCR web lookup is optional and may require internet.
