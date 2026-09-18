import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:visionmate/features/ocr_reader/data/ocr_data_source.dart';
import 'package:visionmate/features/ocr_reader/domain/ocr_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Real-Time OCR Reader & Contextual Web Assistance System Accuracy Suite', () {
    late OcrService ocrService;

    setUp(() {
      ocrService = OcrService();
    });

    // -------------------------------------------------------------------------
    // TEST 1: 2-Pass Natural Reading Order Spatial Sorting Accuracy
    // -------------------------------------------------------------------------
    test('[OCR-ACC-01] Single-Column Natural Top-to-Bottom Reading Order Sorting', () {
      final block1 = OcrTextBlock(text: 'Title: Patient Health Summary', boundingBox: const Rect.fromLTRB(20, 10, 300, 40));
      final block2 = OcrTextBlock(text: 'Date: 2026-09-11', boundingBox: const Rect.fromLTRB(20, 50, 200, 75));
      final block3 = OcrTextBlock(text: 'Diagnosis: Seasonal Allergies', boundingBox: const Rect.fromLTRB(20, 90, 280, 115));
      final block4 = OcrTextBlock(text: 'Prescription: Cetirizine 10mg', boundingBox: const Rect.fromLTRB(20, 130, 320, 155));

      // Feed in reverse order
      final input = [block4, block3, block2, block1];
      final sorted = OcrService.sortTextBlocksInReadingOrder(input);

      expect(sorted[0].text, equals('Title: Patient Health Summary'));
      expect(sorted[1].text, equals('Date: 2026-09-11'));
      expect(sorted[2].text, equals('Diagnosis: Seasonal Allergies'));
      expect(sorted[3].text, equals('Prescription: Cetirizine 10mg'));
    });

    // -------------------------------------------------------------------------
    // TEST 2: Horizontal Line-Band Thresholding (Delta Y <= 20.0 px)
    // -------------------------------------------------------------------------
    test('[OCR-ACC-02] Same-Line Word Band Thresholding (Left-to-Right Ordering)', () {
      // 3 words on the same horizontal line, with minor vertical jitter within 20px
      // Word 1: 'First' at top=100.0, left=50.0
      // Word 2: 'Middle' at top=108.0 (diff=8 <= 20), left=160.0
      // Word 3: 'Last' at top=95.0 (diff=5 <= 20 relative to 100), left=280.0
      final w1 = OcrTextBlock(text: 'First', boundingBox: const Rect.fromLTRB(50, 100, 140, 130));
      final w2 = OcrTextBlock(text: 'Middle', boundingBox: const Rect.fromLTRB(160, 108, 260, 138));
      final w3 = OcrTextBlock(text: 'Last', boundingBox: const Rect.fromLTRB(280, 95, 370, 125));

      // Shuffled input: Middle, Last, First
      final sorted = OcrService.sortTextBlocksInReadingOrder([w2, w3, w1]);

      // All words within line band (bandThreshold = 20.0): must sort left to right
      expect(sorted.map((b) => b.text).toList(), equals(['First', 'Middle', 'Last']));
    });

    // -------------------------------------------------------------------------
    // TEST 3: Multi-Line Separation (Delta Y > 20.0 px)
    // -------------------------------------------------------------------------
    test('[OCR-ACC-03] Multi-Line Vertical Boundary Separation (Top-to-Bottom Precedence)', () {
      // Line 1: 'Line One' at top=50.0, left=100.0
      // Line 2: 'Line Two' at top=85.0 (diff=35 > 20), left=20.0 (starts further left)
      final line1 = OcrTextBlock(text: 'Line One', boundingBox: const Rect.fromLTRB(100, 50, 250, 75));
      final line2 = OcrTextBlock(text: 'Line Two', boundingBox: const Rect.fromLTRB(20, 85, 180, 110));

      final sorted = OcrService.sortTextBlocksInReadingOrder([line2, line1]);

      // Even though line2 has smaller left coordinate (20 < 100), it is vertically below line1 (85 > 50 by 35px)
      expect(sorted[0].text, equals('Line One'));
      expect(sorted[1].text, equals('Line Two'));
    });

    // -------------------------------------------------------------------------
    // TEST 4: End-to-End Extraction with Reading Order Assembly
    // -------------------------------------------------------------------------
    test('[OCR-ACC-04] Full End-to-End Extraction with Block Assembly and Whitespace Preservation', () async {
      final mockDataSource = MockAccuracyOcrDataSource(blocks: [
        OcrTextBlock(text: 'Paragraph 2', boundingBox: const Rect.fromLTRB(20, 120, 300, 160)),
        OcrTextBlock(text: 'Document Header', boundingBox: const Rect.fromLTRB(20, 20, 300, 50)),
        OcrTextBlock(text: 'Paragraph 1', boundingBox: const Rect.fromLTRB(20, 70, 300, 100)),
      ]);

      final service = OcrService(dataSource: mockDataSource);
      final text = await service.recognizeTextFromImage('dummy_image.jpg');

      expect(text, equals('Document Header\n\nParagraph 1\n\nParagraph 2'));
      expect(service.state, equals(OcrReaderState.reading));
    });

    // -------------------------------------------------------------------------
    // TEST 5: Empty Text and Error States
    // -------------------------------------------------------------------------
    test('[OCR-ACC-05] No Text Detected & Error Handling State Machine Accuracy', () async {
      // Case 1: Empty blocks returned
      final emptyDataSource = MockAccuracyOcrDataSource(blocks: []);
      final emptyService = OcrService(dataSource: emptyDataSource);
      final emptyResult = await emptyService.recognizeTextFromImage('empty_page.jpg');
      expect(emptyResult, equals('NO_TEXT_FOUND'));
      expect(emptyService.state, equals(OcrReaderState.idle));

      // Case 2: Exception thrown by ML Kit
      final errorDataSource = MockAccuracyOcrDataSource(shouldThrow: true);
      final errorService = OcrService(dataSource: errorDataSource);
      final errorResult = await errorService.recognizeTextFromImage('corrupt_page.jpg');
      expect(errorResult, equals('EXTRACTION_ERROR'));
      expect(errorService.state, equals(OcrReaderState.error));
    });

    // -------------------------------------------------------------------------
    // TEST 6: Contextual Web Lookup Query Distillation (Top 3 Terms)
    // -------------------------------------------------------------------------
    test('[OCR-ACC-06] Contextual Web Query Distillation (Top 3 Terms Extraction)', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.toString(), contains('Acetaminophen%20500mg%20tablets'));
        return http.Response(
          '{"extract":"Acetaminophen is a medication used to treat pain and fever."}',
          200,
        );
      });

      // Query with 6 words: only top 3 should be used
      const query = 'Acetaminophen 500mg tablets oral pain reliever';
      final context = await ocrService.fetchWebContext(query, client: mockClient);

      expect(context, contains('Acetaminophen is a medication used to treat pain and fever.'));
    });

    // -------------------------------------------------------------------------
    // TEST 7: Contextual Web Lookup Offline Resilience
    // -------------------------------------------------------------------------
    test('[OCR-ACC-07] Offline Network Resilience Returns Controlled Graceful Message Without Throwing', () async {
      final mockFailingClient = MockClient((request) async {
        throw http.ClientException('Connection refused / device offline');
      });

      final result = await ocrService.fetchWebContext('Penicillin antibiotic dosage', client: mockFailingClient);
      expect(result, equals('No additional context available.'));
    });
  });
}

// -----------------------------------------------------------------------------
// Test Doubles
// -----------------------------------------------------------------------------
class MockAccuracyOcrDataSource extends OcrDataSource {
  final List<OcrTextBlock> blocks;
  final bool shouldThrow;

  MockAccuracyOcrDataSource({this.blocks = const [], this.shouldThrow = false});

  @override
  Future<List<OcrTextBlock>> extractTextBlocks(String imagePath) async {
    if (shouldThrow) {
      throw Exception('Simulated native ML Kit text recognition failure');
    }
    return blocks;
  }
}
