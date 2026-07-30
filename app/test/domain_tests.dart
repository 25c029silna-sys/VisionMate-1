import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:visionmate/features/braille/domain/braille_service.dart';
import 'package:visionmate/features/digital_library/domain/library_service.dart';
import 'package:visionmate/features/ocr_reader/domain/ocr_service.dart';
import 'package:visionmate/features/scene_navigation/domain/scene_service.dart';
import 'package:visionmate/features/emergency_sos/domain/emergency_service.dart';

class _FakeEmbeddingStore {
  Future<List<Map<String, dynamic>>> fetchEmbeddings() async {
    return [
      {'document_id': 1, 'vector': '[0.1, 0.2, 0.3]'},
      {'document_id': 2, 'vector': '[0.2, 0.1, 0.4]'},
    ];
  }
}

void main() {
  test('BrailleService returns placeholder text', () async {
    final service = BrailleService();
    final result = await service.classifyBraille('image.jpg');
    expect(result, contains('placeholder'));
  });

  test('LibraryService ranks documents by cosine similarity', () async {
    final embeddingStore = _FakeEmbeddingStore();
    final service = LibraryService(embeddingStore as dynamic);
    final results = await service.rankDocuments([0.1, 0.2, 0.3]);
    expect(results, isNotEmpty);
    expect(results.first['document_id'], isNotNull);
  });

  test('OcrService returns placeholder OCR text', () async {
    final service = OcrService();
    final text = await service.recognizeTextFromImage('image.jpg');
    expect(text, contains('placeholder'));
  });

  test('SceneService describes scene placeholder', () async {
    final service = SceneService();
    final text = await service.describeScene();
    expect(text, contains('placeholder'));
  });

  test('EmergencyService composes valid SOS message', () {
    final service = EmergencyService();
    final message = service.composeMessage(
      Position(
        latitude: 1.0,
        longitude: 2.0,
        timestamp: DateTime.now(),
        accuracy: 0.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      ),
    );
    expect(message, contains('1.0'));
    expect(message, contains('2.0'));
  });
}
