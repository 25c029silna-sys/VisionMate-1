import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../../core/pdf/pdf_service.dart';
import '../../../core/tflite/tflite_helper.dart';
import '../../ocr_reader/domain/ocr_service.dart';
import '../data/embedding_store.dart';
import 'minilm_embedder.dart';

class LibraryService {
  final EmbeddingStore embeddingStore;
  final TfliteHelper _tfliteHelper = TfliteHelper();
  final MiniLmEmbedder embedder = MiniLmEmbedder();
  final PdfService pdfService;
  final OcrService ocrService;
  bool _isModelAvailable = false;

  bool get isModelAvailable => _isModelAvailable;

  LibraryService(
    this.embeddingStore, {
    PdfService? pdfService,
    OcrService? ocrService,
  })  : pdfService = pdfService ?? PdfService(),
        ocrService = ocrService ?? OcrService();

  Future<bool> checkModelAvailability() async {
    final interpreter = await _tfliteHelper.loadModel('assets/models/minilm.tflite');
    _isModelAvailable = interpreter != null;
    return _isModelAvailable;
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 0.0;
    double dot = 0.0;
    double magA = 0.0;
    double magB = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      magA += a[i] * a[i];
      magB += b[i] * b[i];
    }
    magA = sqrt(magA);
    magB = sqrt(magB);
    if (magA == 0 || magB == 0) return 0.0;
    return dot / (magA * magB);
  }

  /// Indexes a new document by creating SQLite record and 384d vector embedding.
  Future<int> addAndIndexDocument(String title, String text, {String sourceType = 'user_note'}) async {
    final docId = await embeddingStore.service.saveDocument({
      'title': title,
      'text': text,
      'source_type': sourceType,
      'created_at': DateTime.now().toIso8601String(),
    });
    final vector = embedder.generateEmbedding('$title $text');
    await embeddingStore.saveEmbedding(docId, vector);
    return docId;
  }

  /// Imports a PDF file, extracts all page text, saves to SQLite database, and computes vector embeddings.
  /// If the PDF contains no extractable programmatic text layer (scanned/image PDF), it triggers an
  /// automatic on-device OCR fallback to extract and index text from page images.
  Future<int> importAndIndexPdf(File pdfFile) async {
    final fileName = pdfFile.path.split(Platform.pathSeparator).last;
    final title = fileName.replaceAll('.pdf', '').replaceAll('_', ' ');
    
    // 1. Attempt fast native text layer extraction
    var extractedText = await pdfService.extractTextFromPdf(pdfFile);
    String sourceType = 'pdf_import';

    // 2. If no text layer exists (scanned/image PDF), fall back to OCR
    if (extractedText.trim().isEmpty) {
      debugPrint('LibraryService: No programmatic text layer found in "$fileName". Initiating OCR fallback...');
      final pageImages = await pdfService.extractImagesFromPdf(pdfFile);
      
      if (pageImages.isNotEmpty) {
        final ocrResults = <String>[];
        for (final pageImg in pageImages) {
          final pageText = await ocrService.recognizeTextFromImage(pageImg.path);
          if (pageText.isNotEmpty && pageText != 'NO_TEXT_FOUND' && pageText != 'EXTRACTION_ERROR') {
            ocrResults.add(pageText);
          }
        }
        if (ocrResults.isNotEmpty) {
          extractedText = ocrResults.join('\n\n--- Page Break ---\n\n');
          sourceType = 'scanned_pdf_ocr';
          debugPrint('LibraryService: Successfully extracted OCR text from ${pageImages.length} PDF pages.');
        }
      }
    }

    final textToIndex = extractedText.isNotEmpty
        ? extractedText
        : 'Scanned PDF Document containing no recognizable text layer.';
    
    return await addAndIndexDocument(title, textToIndex, sourceType: sourceType);
  }

  /// Generates vector embedding and ranks documents for a spoken search query string.
  Future<List<Map<String, dynamic>>> searchBySpokenQuery(
    String queryText, {
    int topK = 10,
  }) async {
    final queryVector = embedder.generateEmbedding(queryText);
    return rankDocuments(queryVector, topK: topK);
  }

  /// Ranks documents by computing cosine similarity against ALL stored vector embeddings.
  Future<List<Map<String, dynamic>>> rankDocuments(
    List<double> queryEmbedding, {
    int topK = 10,
  }) async {
    final rows = await embeddingStore.fetchEmbeddings();
    Map<int, Map<String, dynamic>> docMap = {};
    try {
      final docs = await embeddingStore.service.fetchDocuments();
      docMap = {for (var d in docs) d['id'] as int: d};
    } catch (_) {
      // Test environment or uninitialized DB fallback
    }

    final scored = rows.map((row) {
      final docId = row['document_id'] as int;
      final doc = docMap[docId] ?? {'title': 'Document #$docId', 'text': ''};
      final vector = List<double>.from(jsonDecode(row['vector']) as List<dynamic>);
      final score = _cosineSimilarity(queryEmbedding, vector);
      return {
        'document_id': docId,
        'title': doc['title'],
        'text': doc['text'],
        'source_type': doc['source_type'],
        'score': score,
      };
    }).toList();

    // Sort descending by similarity score
    scored.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));

    // Return top-K matches post-scoring
    return scored.take(topK).toList();
  }
}

