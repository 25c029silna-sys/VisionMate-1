import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:http/http.dart' as http;
import 'package:visionmate/features/ocr_reader/data/ocr_data_source.dart';
import 'package:visionmate/features/ocr_reader/domain/ocr_service.dart';

class MockOcrDataSource extends Mock implements OcrDataSource {}
class MockHttpClient extends Mock implements http.Client {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  group('OcrService Unit Tests', () {
    late MockOcrDataSource mockDataSource;
    late OcrService service;

    setUp(() {
      mockDataSource = MockOcrDataSource();
      service = OcrService(dataSource: mockDataSource);
    });

    test('Assembles multi-block text in correct top-to-bottom reading order', () async {
      final blocks = [
        OcrTextBlock(
          text: 'Second line of text.',
          boundingBox: const Rect.fromLTWH(10, 100, 200, 30),
        ),
        OcrTextBlock(
          text: 'First line of text.',
          boundingBox: const Rect.fromLTWH(10, 10, 200, 30),
        ),
      ];

      when(() => mockDataSource.extractTextBlocks('test_image.jpg'))
          .thenAnswer((_) async => blocks);

      final result = await service.recognizeTextFromImage('test_image.jpg');

      expect(result, equals('First line of text.\n\nSecond line of text.'));
      expect(service.state, equals(OcrReaderState.reading));
    });

    test('Returns NO_TEXT_FOUND when OCR detects no blocks', () async {
      when(() => mockDataSource.extractTextBlocks('empty_image.jpg'))
          .thenAnswer((_) async => []);

      final result = await service.recognizeTextFromImage('empty_image.jpg');

      expect(result, equals('NO_TEXT_FOUND'));
    });

    test('Returns EXTRACTION_ERROR and logs safely when OcrDataSource throws exception', () async {
      when(() => mockDataSource.extractTextBlocks('corrupt_image.jpg'))
          .thenThrow(Exception('ML Kit native error'));

      final result = await service.recognizeTextFromImage('corrupt_image.jpg');

      expect(result, equals('EXTRACTION_ERROR'));
      expect(service.state, equals(OcrReaderState.error));
    });

    test('Optional web context failure/timeout does NOT interrupt or corrupt core reading result', () async {
      final mockClient = MockHttpClient();
      when(() => mockClient.get(any())).thenThrow(Exception('Network offline'));

      const coreExtractedText = 'First line of text.\n\nSecond line of text.';
      final contextResult = await service.fetchWebContext(coreExtractedText, client: mockClient);

      // Web context lookup fails silently with fallback, leaving core text untouched
      expect(contextResult, equals('No additional context available.'));
      expect(coreExtractedText, contains('First line of text.'));
    });
  });
}
