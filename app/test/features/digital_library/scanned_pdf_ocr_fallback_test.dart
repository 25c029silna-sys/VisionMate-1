import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:visionmate/core/pdf/pdf_service.dart';
import 'package:visionmate/core/storage/storage_service.dart';
import 'package:visionmate/features/digital_library/data/embedding_store.dart';
import 'package:visionmate/features/digital_library/domain/library_service.dart';
import 'package:visionmate/features/ocr_reader/domain/ocr_service.dart';

class MockPdfService extends Mock implements PdfService {}
class MockOcrService extends Mock implements OcrService {}

class TestEmbeddingStore extends EmbeddingStore {
  final List<Map<String, dynamic>> _docs = [];
  final List<Map<String, dynamic>> _embeddings = [];

  TestEmbeddingStore() : super(StorageService());

  @override
  StorageService get service => _MockStorageService(this);

  @override
  Future<int> saveEmbedding(int documentId, List<double> vector) async {
    _embeddings.add({
      'id': _embeddings.length + 1,
      'document_id': documentId,
      'vector': jsonEncode(vector),
    });
    return _embeddings.length;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchEmbeddings({int? limit}) async {
    return List.from(_embeddings);
  }
}

class _MockStorageService extends StorageService {
  final TestEmbeddingStore store;
  _MockStorageService(this.store);

  @override
  Future<int> saveDocument(Map<String, dynamic> doc) async {
    final docId = store._docs.length + 1;
    store._docs.add({
      'id': docId,
      ...doc,
    });
    return docId;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchDocuments() async {
    return List.from(store._docs);
  }

  @override
  Future<int> deleteDocument(int id) async {
    store._embeddings.removeWhere((e) => e['document_id'] == id);
    final count = store._docs.where((d) => d['id'] == id).length;
    store._docs.removeWhere((d) => d['id'] == id);
    return count;
  }
}

void main() {
  group('Braille PDF & Digital Library Integration Tests', () {
    late MockPdfService mockPdfService;
    late MockOcrService mockOcrService;
    late TestEmbeddingStore testStore;
    late LibraryService libraryService;

    setUp(() {
      mockPdfService = MockPdfService();
      mockOcrService = MockOcrService();
      testStore = TestEmbeddingStore();

      libraryService = LibraryService(
        testStore,
        pdfService: mockPdfService,
        ocrService: mockOcrService,
      );
    });

    test('addAndIndexDocument indexes Braille PDF output under braille_pdf source type', () async {
      final docId = await libraryService.addAndIndexDocument(
        'Braille Document (2026-08-26 01:00)',
        'Chapter 1: The laws of classical mechanics and gravitational forces.',
        sourceType: 'braille_pdf',
      );

      expect(docId, equals(1));
      final docs = await testStore.service.fetchDocuments();
      expect(docs, hasLength(1));
      expect(docs.first['title'], contains('Braille Document'));
      expect(docs.first['source_type'], equals('braille_pdf'));
      expect(docs.first['text'], contains('classical mechanics'));

      // Perform semantic search on Braille PDF
      final results = await libraryService.searchBySpokenQuery('gravitational forces in physics', topK: 1);
      expect(results, isNotEmpty);
      expect(results.first['document_id'], equals(1));
      expect(results.first['title'], contains('Braille Document'));
    });

    test('importAndIndexPdf indexes extractable text directly under pdf_import', () async {
      final fakePdf = File('chemistry_notes.pdf');
      when(() => mockPdfService.extractTextFromPdf(fakePdf))
          .thenAnswer((_) async => 'Periodic table and molecular chemical bonds.');

      final docId = await libraryService.importAndIndexPdf(fakePdf);

      expect(docId, equals(1));
      final docs = await testStore.service.fetchDocuments();
      expect(docs, hasLength(1));
      expect(docs.first['title'], equals('chemistry notes'));
      expect(docs.first['text'], contains('Periodic table'));
      expect(docs.first['source_type'], equals('pdf_import'));
      verifyNever(() => mockOcrService.recognizeTextFromImage(any()));
    });

    test('importAndIndexPdf triggers OCR fallback when PDF has no extractable text layer', () async {
      final fakeScannedPdf = File('scanned_medical_prescription.pdf');
      final page1Img = File('temp/page_0.jpg');
      final page2Img = File('temp/page_1.jpg');

      // 1. Native text extraction returns empty string (scanned/image PDF)
      when(() => mockPdfService.extractTextFromPdf(fakeScannedPdf))
          .thenAnswer((_) async => '');

      // 2. Embedded image extraction returns 2 page bitmaps
      when(() => mockPdfService.extractImagesFromPdf(fakeScannedPdf))
          .thenAnswer((_) async => [page1Img, page2Img]);

      // 3. OCR recognizes text on each page image
      when(() => mockOcrService.recognizeTextFromImage('temp/page_0.jpg'))
          .thenAnswer((_) async => 'Prescription: Take 500mg Amoxicillin twice daily with water.');
      when(() => mockOcrService.recognizeTextFromImage('temp/page_1.jpg'))
          .thenAnswer((_) async => 'Doctor signature and clinic contact details.');

      final docId = await libraryService.importAndIndexPdf(fakeScannedPdf);

      expect(docId, equals(1));
      final docs = await testStore.service.fetchDocuments();
      expect(docs, hasLength(1));
      expect(docs.first['title'], equals('scanned medical prescription'));
      expect(docs.first['source_type'], equals('scanned_pdf_ocr'));
      expect(docs.first['text'], contains('500mg Amoxicillin'));
      expect(docs.first['text'], contains('Doctor signature'));

      // Verify that vector search matches the OCR-extracted content
      final searchResults = await libraryService.searchBySpokenQuery('Amoxicillin prescription', topK: 1);
      expect(searchResults, isNotEmpty);
      expect(searchResults.first['document_id'], equals(1));
      expect(searchResults.first['title'], equals('scanned medical prescription'));
    });
  });
}

