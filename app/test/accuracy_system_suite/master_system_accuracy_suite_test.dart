import 'package:flutter_test/flutter_test.dart';
import 'braille_system_accuracy_test.dart' as braille_suite;
import 'digital_library_system_accuracy_test.dart' as library_suite;
import 'emergency_sos_accuracy_test.dart' as emergency_suite;
import 'ocr_reader_system_accuracy_test.dart' as ocr_suite;
import 'scene_navigation_accuracy_test.dart' as scene_suite;
import 'voice_commands_accuracy_test.dart' as voice_suite;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VisionMate Master Live System Accuracy & Module Performance Suite', () {
    group('Module 1: Braille Recognition & Digitization Pipeline', () {
      braille_suite.main();
    });

    group('Module 2: Smart Digital Library & Semantic Vector Search', () {
      library_suite.main();
    });

    group('Module 3: Real-Time OCR Reader & Contextual Web Assistance', () {
      ocr_suite.main();
    });

    group('Module 4: Real-Time Scene Description & Indoor Navigation', () {
      scene_suite.main();
    });

    group('Module 5: Gesture & Voice-Triggered Emergency SOS', () {
      emergency_suite.main();
    });

    group('Module 6: Voice UI & ASR Command Router', () {
      voice_suite.main();
    });
  });
}
