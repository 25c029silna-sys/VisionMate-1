import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionmate/core/pdf/pdf_service.dart';
import 'package:visionmate/core/storage/storage_service.dart';
import 'package:visionmate/features/digital_library/data/embedding_store.dart';
import 'package:visionmate/features/digital_library/domain/library_service.dart';
import 'package:visionmate/features/digital_library/domain/minilm_embedder.dart';
import 'package:visionmate/features/ocr_reader/domain/ocr_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Smart Digital Library & Semantic Vector Search System Accuracy Suite', () {
    late MiniLmEmbedder embedder;

    setUp(() {
      embedder = MiniLmEmbedder();
    });

    // -------------------------------------------------------------------------
    // TEST 1: L2 Normalization Invariance Across Varied Text Lengths
    // -------------------------------------------------------------------------
    test('[LIB-ACC-01] 384-Dimensional MiniLM Vector L2 Normalization Invariance', () {
      final testPhrases = [
        'medical prescription',
        'Blind user navigation guide for indoor staircases and doorways',
        'The quick brown fox jumps over the lazy dog in a sunny afternoon',
        'SingleWord',
        'Numbers 123 456 789 and punctuation! @# \$% ^&*()',
      ];

      for (final phrase in testPhrases) {
        final vector = embedder.generateEmbedding(phrase);
        expect(vector.length, equals(384));

        double sumSq = 0.0;
        for (final val in vector) {
          sumSq += val * val;
        }

        // L2 Norm = sqrt(sum(x^2)) must equal 1.0 within floating point tolerance
        final norm = sqrt(sumSq);
        expect(norm, closeTo(1.0, 0.001), reason: 'Vector for "$phrase" must be L2-normalized.');
      }
    });

    // -------------------------------------------------------------------------
    // TEST 2: Empty and Edge-Case Text Input Handling
    // -------------------------------------------------------------------------
    test('[LIB-ACC-02] Zero-Vector Generation on Empty or Whitespace-Only Text', () {
      final emptyVector = embedder.generateEmbedding('');
      expect(emptyVector.length, equals(384));
      expect(emptyVector.every((x) => x == 0.0), isTrue);

      final whitespaceVector = embedder.generateEmbedding('   \n\t   ');
      expect(whitespaceVector.every((x) => x == 0.0), isTrue);

      final punctVector = embedder.generateEmbedding('!@#\$%^&*()');
      expect(punctVector.every((x) => x == 0.0), isTrue);
    });

    // -------------------------------------------------------------------------
    // TEST 3: Semantic Margin Separation (Relevant vs Distractor)
    // -------------------------------------------------------------------------
    test('[LIB-ACC-03] Cosine Similarity Discriminability & Separation Margin', () {
      // Positive pair: query and relevant document with shared domain vocabulary
      const query = 'indoor navigation obstacle guide';
      const positiveDoc = 'indoor navigation obstacle guide for detecting stairs and doors for the blind';
      // Distractor doc: completely unrelated domain
      const distractorDoc = 'chocolate chip cookie recipe with baking flour and vanilla extract';

      final qVec = embedder.generateEmbedding(query);
      final pVec = embedder.generateEmbedding(positiveDoc);
      final dVec = embedder.generateEmbedding(distractorDoc);

      double cosineSim(List<double> a, List<double> b) {
        double dot = 0.0;
        for (int i = 0; i < a.length; i++) {
          dot += a[i] * b[i];
        }
        return dot;
      }

      final posSim = cosineSim(qVec, pVec);
      final distSim = cosineSim(qVec, dVec);

      expect(posSim, greaterThan(0.50), reason: 'Relevant document must have strong similarity (>0.50).');
      expect(distSim, lessThan(0.10), reason: 'Unrelated distractor must have near zero similarity (<0.10).');

      final margin = posSim - distSim;
      expect(margin, greaterThan(0.40), reason: 'Margin separation between positive and distractor must exceed 0.40.');
    });

    // -------------------------------------------------------------------------
    // TEST 4: Top-1 and Top-K Multi-Document Corpus Ranking Accuracy
    // -------------------------------------------------------------------------
    test('[LIB-ACC-04] Top-1 and Top-K Document Retrieval Accuracy Across Multi-Domain Corpus', () async {
      final store = AccuracyFakeEmbeddingStore();
      final library = LibraryService(store);

      // Corpus of 5 distinct documents across different life domains
      final documents = [
        {'id': 101, 'title': 'Medical Prescription', 'text': 'Amoxicillin 500mg take twice daily with food for 7 days. Call clinic for refill.'},
        {'id': 102, 'title': 'Indoor Navigation Manual', 'text': 'Guidelines for navigating hallways, locating stairways, and avoiding obstacle collisions.'},
        {'id': 103, 'title': 'Bank Statement Overview', 'text': 'Monthly balance summary, checking account deposits, electronic wire transfers, and ATM fee charges.'},
        {'id': 104, 'title': 'Braille Contraction Guide', 'text': 'Unified English Braille Grade 2 contractions, dot indicators, and cell symbol tables.'},
        {'id': 105, 'title': 'Public Transit Schedule', 'text': 'Subway timetable, bus departure gates, commuter train line connections, and ticket payment.'},
      ];

      for (final doc in documents) {
        final vec = embedder.generateEmbedding('${doc['title']} ${doc['text']}');
        await store.saveDocumentWithEmbedding(doc['id'] as int, doc['title'] as String, doc['text'] as String, vec);
      }

      // Benchmark queries and expected Top-1 Document ID
      final testCases = [
        {'query': 'refill prescription antibiotic pills', 'expectedId': 101},
        {'query': 'hallway obstacle navigation steps', 'expectedId': 102},
        {'query': 'monthly banking checking deposit balance', 'expectedId': 103},
        {'query': 'grade 2 braille symbols contractions', 'expectedId': 104},
        {'query': 'subway train bus transit departure', 'expectedId': 105},
      ];

      int top1Hits = 0;
      for (final tc in testCases) {
        final query = tc['query'] as String;
        final expectedId = tc['expectedId'] as int;

        final results = await library.searchBySpokenQuery(query, topK: 3);
        expect(results, isNotEmpty);

        final topHit = results.first;
        if (topHit['document_id'] == expectedId) {
          top1Hits++;
        }
      }

      final top1Accuracy = (top1Hits / testCases.length) * 100.0;
      expect(top1Accuracy, equals(100.0), reason: 'Top-1 Retrieval Accuracy across domain benchmark should be 100%.');
    });

    // -------------------------------------------------------------------------
    // TEST 5: Spoken Query Conversational Voice Input Matching Accuracy
    // -------------------------------------------------------------------------
    test('[LIB-ACC-05] Natural Spoken Voice Query Conversational Search Accuracy', () async {
      final store = AccuracyFakeEmbeddingStore();
      final library = LibraryService(store);

      final vec1 = embedder.generateEmbedding('Emergency SOS contacts and hospital hotline numbers');
      final vec2 = embedder.generateEmbedding('Recipe for cooking chicken soup broth');
      await store.saveDocumentWithEmbedding(201, 'Emergency SOS', 'Hospital numbers', vec1);
      await store.saveDocumentWithEmbedding(202, 'Cooking Soup', 'Chicken broth recipe', vec2);

      // Conversational query with speech fillers: "Um can you please find emergency contact info thanks"
      final results = await library.searchBySpokenQuery('um can you please find emergency contact hospital thanks');
      expect(results.first['document_id'], equals(201));
      expect((results.first['score'] as double), greaterThan(0.20));
    });

    // -------------------------------------------------------------------------
    // TEST 6: Scanned PDF Fallback to OCR Pipeline Accuracy
    // -------------------------------------------------------------------------
    test('[LIB-ACC-06] Scanned PDF Import Triggers Automatic OCR Fallback and Indexes Extracted Text', () async {
      final store = AccuracyFakeEmbeddingStore();
      final mockPdfService = MockAccuracyPdfService(hasTextLayer: false);
      final mockOcrService = MockAccuracyOcrService();

      final library = LibraryService(
        store,
        pdfService: mockPdfService,
        ocrService: mockOcrService,
      );

      final dummyFile = File('scanned_medical_record.pdf');
      final docId = await library.importAndIndexPdf(dummyFile);

      expect(docId, greaterThan(0));
      final savedDoc = store.getDocument(docId);
      expect(savedDoc, isNotNull);
      expect(savedDoc!['source_type'], equals('scanned_pdf_ocr'));
      expect(savedDoc['text'], contains('Extracted OCR Page 1'));
      expect(savedDoc['text'], contains('Extracted OCR Page 2'));
    });
  });
}

// -----------------------------------------------------------------------------
// Test Doubles & Mock Helpers
// -----------------------------------------------------------------------------
class AccuracyFakeStorageService extends Fake implements StorageService {
  final Map<int, Map<String, dynamic>> docs;
  int _idCounter = 300;

  AccuracyFakeStorageService(this.docs);

  @override
  Future<int> saveDocument(Map<String, dynamic> doc) async {
    _idCounter++;
    docs[_idCounter] = {
      'id': _idCounter,
      ...doc,
    };
    return _idCounter;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchDocuments() async {
    return docs.values.toList();
  }
}

class AccuracyFakeEmbeddingStore extends EmbeddingStore {
  final List<Map<String, dynamic>> _embeddings = [];
  final Map<int, Map<String, dynamic>> _documents;

  AccuracyFakeEmbeddingStore._(this._documents, AccuracyFakeStorageService storageService)
      : super(storageService);

  factory AccuracyFakeEmbeddingStore() {
    final docs = <int, Map<String, dynamic>>{};
    return AccuracyFakeEmbeddingStore._(docs, AccuracyFakeStorageService(docs));
  }

  Future<void> saveDocumentWithEmbedding(int docId, String title, String text, List<double> vector) async {
    _documents[docId] = {
      'id': docId,
      'title': title,
      'text': text,
      'source_type': 'test_doc',
    };
    await saveEmbedding(docId, vector);
  }

  Map<String, dynamic>? getDocument(int docId) => _documents[docId];

  @override
  Future<int> saveEmbedding(int documentId, List<double> vector) async {
    _embeddings.add({
      'document_id': documentId,
      'vector': jsonEncode(vector),
    });
    return _embeddings.length;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchEmbeddings({int? limit}) async {
    if (limit != null) {
      return _embeddings.take(limit).toList();
    }
    return List.from(_embeddings);
  }
}

class MockAccuracyPdfService extends PdfService {
  final bool hasTextLayer;

  MockAccuracyPdfService({required this.hasTextLayer});

  @override
  Future<String> extractTextFromPdf(File file) async {
    return hasTextLayer ? 'Programmatic native text content.' : '';
  }

  @override
  Future<List<File>> extractImagesFromPdf(File file) async {
    return [File('page1.png'), File('page2.png')];
  }
}

class MockAccuracyOcrService extends OcrService {
  int _callCount = 0;

  @override
  Future<String> recognizeTextFromImage(String imagePath) async {
    _callCount++;
    return 'Extracted OCR Page $_callCount content: Patient medical diagnosis and prescription details.';
  }
}
