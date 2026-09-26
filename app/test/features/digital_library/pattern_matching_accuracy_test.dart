import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionmate/core/storage/storage_service.dart';
import 'package:visionmate/features/digital_library/data/embedding_store.dart';
import 'package:visionmate/features/digital_library/domain/library_service.dart';
import 'package:visionmate/features/digital_library/domain/minilm_embedder.dart';

class TestPatternEmbeddingStore extends EmbeddingStore {
  final Map<int, Map<String, dynamic>> _docs = {};
  final List<Map<String, dynamic>> _embeddings = [];

  TestPatternEmbeddingStore() : super(StorageService());

  void addDocument(int id, String title, String text, List<double> vector) {
    _docs[id] = {
      'id': id,
      'title': title,
      'text': text,
      'source_type': 'test_doc',
    };
    _embeddings.add({
      'document_id': id,
      'vector': '[${vector.join(',')}]',
    });
  }

  @override
  Future<List<Map<String, dynamic>>> fetchEmbeddings({int? limit}) async {
    return List.from(_embeddings);
  }
}

void main() {
  group('Enhanced Semantic Pattern Matching Accuracy Evaluation', () {
    late MiniLmEmbedder embedder;

    setUp(() {
      embedder = MiniLmEmbedder();
    });

    double cosineSim(List<double> a, List<double> b) {
      if (a.length != b.length || a.isEmpty) return 0.0;
      double dot = 0.0, magA = 0.0, magB = 0.0;
      for (int i = 0; i < a.length; i++) {
        dot += a[i] * b[i];
        magA += a[i] * a[i];
        magB += b[i] * b[i];
      }
      magA = sqrt(magA);
      magB = sqrt(magB);
      if (magA == 0 || magB == 0) return 0.0;
      return (dot / (magA * magB)).clamp(0.0, 1.0);
    }

    test('1. Conversational Speech Query Resilience: Closeness Score Boost', () {
      final docText = 'Emergency SOS contacts and hospital hotline numbers';
      final docVec = embedder.generateEmbedding(docText);

      // Clean query
      final cleanQueryVec = embedder.generateEmbedding('emergency contacts hospital');
      final cleanScore = cosineSim(cleanQueryVec, docVec);

      // Conversational query with speech fillers: "um can you please find emergency contact hospital thanks"
      final spokenQueryVec = embedder.generateEmbedding('um can you please find emergency contact hospital thanks');
      final spokenScore = cosineSim(spokenQueryVec, docVec);

      print('Clean Query Score: ${(cleanScore * 100).toStringAsFixed(1)}%');
      print('Spoken Filler Query Score: ${(spokenScore * 100).toStringAsFixed(1)}%');

      // Enhanced algorithm retains high semantic energy (> 55%) despite 6 filler words
      expect(spokenScore, greaterThan(0.55));
      expect(spokenScore, closeTo(cleanScore, 0.25));
    });

    test('2. Morphological Variation Bridging (Plurals, Gerunds, Past Tense)', () {
      // Document uses base form: "refill prescription at clinic"
      final docVec = embedder.generateEmbedding('refill prescription at clinic');

      // User asks using plural and gerund: "refilling prescriptions at clinics"
      final queryVec = embedder.generateEmbedding('refilling prescriptions at clinics');
      final sim = cosineSim(queryVec, docVec);

      print('Morphological Inflection Match Score: ${(sim * 100).toStringAsFixed(1)}%');
      // Suffix stemmer & n-grams bridge the morphological gap with strong similarity (> 55%)
      expect(sim, greaterThan(0.55));
    });

    test('3. Typo and Speech ASR Imperfection Resilience', () {
      // Document: "prescription instructions"
      final docVec = embedder.generateEmbedding('prescription instructions');

      // Speech transcription typo: "prescripion instrucions" (missing 't's)
      final typoQueryVec = embedder.generateEmbedding('prescripion instrucions');
      final typoSim = cosineSim(typoQueryVec, docVec);

      print('Typo Resilience Match Score: ${(typoSim * 100).toStringAsFixed(1)}%');
      // Sub-word character n-grams provide positive overlap even when full words have typos (> 15%)
      expect(typoSim, greaterThan(0.15));
    });

    test('4. Bigram Collocation Discrimination: Phrase Coherence Priority', () {
      // Doc A has exact phrase collocation
      final docA = embedder.generateEmbedding('indoor navigation obstacle guide for the blind');
      // Doc B has the words scattered across unrelated context
      final docB = embedder.generateEmbedding('indoor baking guide for cooking chocolate obstacle cake');

      final queryVec = embedder.generateEmbedding('indoor navigation obstacle');
      final scoreA = cosineSim(queryVec, docA);
      final scoreB = cosineSim(queryVec, docB);

      print('Coherent Phrase Score: ${(scoreA * 100).toStringAsFixed(1)}% vs Disjoint Words Score: ${(scoreB * 100).toStringAsFixed(1)}%');
      expect(scoreA, greaterThan(0.70));
      expect(scoreA - scoreB, greaterThan(0.30));
    });

    test('5. Multi-Document Ranking with Suffix and Filler Invariance', () async {
      final store = TestPatternEmbeddingStore();
      final library = LibraryService(store);

      final doc1 = embedder.generateEmbedding('Emergency SOS contacts and hospital medical help');
      final doc2 = embedder.generateEmbedding('Public transit timetable and bus schedules');
      final doc3 = embedder.generateEmbedding('Monthly banking checking balance statement');

      store.addDocument(1, 'Emergency SOS', 'contacts and hospital', doc1);
      store.addDocument(2, 'Transit Schedule', 'timetable and bus', doc2);
      store.addDocument(3, 'Bank Statement', 'checking balance', doc3);

      // Conversational query with plural inflection
      final results = await library.searchBySpokenQuery('can you please check my banking balances');
      expect(results, isNotEmpty);
      expect(results.first['document_id'], equals(3));
      expect((results.first['score'] as double), greaterThan(0.40));
    });
  });
}
