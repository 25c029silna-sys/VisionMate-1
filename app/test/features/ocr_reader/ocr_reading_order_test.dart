import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionmate/features/ocr_reader/data/ocr_data_source.dart';
import 'package:visionmate/features/ocr_reader/domain/ocr_service.dart';

void main() {
  group('OCR Reading Order Sorting Tests', () {
    test('Sorts text blocks strictly top-to-bottom when vertically separated', () {
      final block1 = OcrTextBlock(
        text: 'Header Text',
        boundingBox: const Rect.fromLTWH(10, 10, 100, 30),
      );
      final block2 = OcrTextBlock(
        text: 'Body Paragraph 1',
        boundingBox: const Rect.fromLTWH(10, 100, 200, 50),
      );
      final block3 = OcrTextBlock(
        text: 'Footer Text',
        boundingBox: const Rect.fromLTWH(10, 300, 100, 20),
      );

      // Input in mixed order
      final input = [block3, block1, block2];
      final sorted = OcrService.sortTextBlocksInReadingOrder(input);

      expect(sorted.map((b) => b.text).toList(), equals([
        'Header Text',
        'Body Paragraph 1',
        'Footer Text',
      ]));
    });

    test('Sorts text blocks left-to-right when within the same horizontal line band (delta <= 20px)', () {
      // Two columns on the same horizontal line band (top ~50px)
      final leftColumn = OcrTextBlock(
        text: 'Left Column',
        boundingBox: const Rect.fromLTWH(10, 50, 100, 40),
      );
      final rightColumn = OcrTextBlock(
        text: 'Right Column',
        boundingBox: const Rect.fromLTWH(150, 55, 100, 40), // 5px top diff <= 20px band
      );

      final input = [rightColumn, leftColumn];
      final sorted = OcrService.sortTextBlocksInReadingOrder(input);

      expect(sorted.first.text, equals('Left Column'));
      expect(sorted.last.text, equals('Right Column'));
    });

    test('Handles multi-column page layout ordering correctly', () {
      final title = OcrTextBlock(
        text: 'Document Title',
        boundingBox: const Rect.fromLTWH(50, 10, 300, 40),
      );
      final col1Header = OcrTextBlock(
        text: 'Section 1',
        boundingBox: const Rect.fromLTWH(10, 80, 100, 30),
      );
      final col2Header = OcrTextBlock(
        text: 'Section 2',
        boundingBox: const Rect.fromLTWH(200, 82, 100, 30), // Same band
      );

      final sorted = OcrService.sortTextBlocksInReadingOrder([col2Header, title, col1Header]);

      expect(sorted[0].text, equals('Document Title'));
      expect(sorted[1].text, equals('Section 1'));
      expect(sorted[2].text, equals('Section 2'));
    });
  });
}
