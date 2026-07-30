import 'package:flutter_test/flutter_test.dart';
import 'package:visionmate/core/tflite/tflite_helper.dart';
import 'package:visionmate/features/braille/domain/braille_service.dart';
import 'package:visionmate/features/scene_navigation/domain/scene_service.dart';
import 'package:visionmate/features/digital_library/domain/library_service.dart';
import 'package:visionmate/features/digital_library/data/embedding_store.dart';
import 'package:visionmate/core/storage/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TFLite Model Fallback Tests', () {
    test('TfliteHelper gracefully handles invalid asset path or corrupt file without throwing', () async {
      final helper = TfliteHelper();
      final interpreter = await helper.loadModel('assets/models/non_existent.tflite');
      expect(interpreter, isNull);
      expect(helper.isModelAvailable, isFalse);
    });

    test('BrailleService returns MODEL_UNAVAILABLE on stub/missing asset without crash', () async {
      final service = BrailleService();
      final result = await service.classifyBraille('test_image.jpg');
      expect(result, equals('MODEL_UNAVAILABLE'));
      expect(service.isModelAvailable, isFalse);
    });

    test('SceneService returns MODEL_UNAVAILABLE on stub/missing asset without crash', () async {
      final service = SceneService();
      final describeResult = await service.describeScene();
      final navResult = await service.navigateIndoors();
      expect(describeResult, equals('MODEL_UNAVAILABLE'));
      expect(navResult, equals('MODEL_UNAVAILABLE'));
      expect(service.isModelAvailable, isFalse);
    });

    test('LibraryService checkModelAvailability handles missing asset safely', () async {
      final service = LibraryService(EmbeddingStore(StorageService()));
      final available = await service.checkModelAvailability();
      expect(available, isFalse);
      expect(service.isModelAvailable, isFalse);
    });
  });
}
