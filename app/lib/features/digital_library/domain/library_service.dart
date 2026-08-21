import 'dart:convert';
import 'dart:io';
import 'dart:math';
import '../../../core/pdf/pdf_service.dart';
import '../../../core/tflite/tflite_helper.dart';
import '../data/embedding_store.dart';
import 'minilm_embedder.dart';

class LibraryService {
  final EmbeddingStore embeddingStore;
  final TfliteHelper _tfliteHelper = TfliteHelper();
  final MiniLmEmbedder embedder = MiniLmEmbedder();
  final PdfService pdfService = PdfService();
  bool _isModelAvailable = false;

  bool get isModelAvailable => _isModelAvailable;

  LibraryService(this.embeddingStore);

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
  Future<int> importAndIndexPdf(File pdfFile) async {
    final fileName = pdfFile.path.split(Platform.pathSeparator).last;
    final title = fileName.replaceAll('.pdf', '').replaceAll('_', ' ');
    
    final extractedText = await pdfService.extractTextFromPdf(pdfFile);
    final textToIndex = extractedText.isNotEmpty ? extractedText : 'PDF Document containing no extractable text layer.';
    
    return await addAndIndexDocument(title, textToIndex, sourceType: 'pdf_import');
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
