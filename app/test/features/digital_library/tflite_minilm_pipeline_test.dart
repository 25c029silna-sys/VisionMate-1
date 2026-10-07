import 'package:flutter_test/flutter_test.dart';
import 'package:visionmate/core/storage/storage_service.dart';
import 'package:visionmate/features/digital_library/data/embedding_store.dart';
import 'package:visionmate/features/digital_library/domain/bert_wordpiece_tokenizer.dart';
import 'package:visionmate/features/digital_library/domain/library_service.dart';
import 'package:visionmate/features/digital_library/domain/minilm_embedder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TFLite MiniLM & WordPiece Tokenizer Pipeline Tests', () {
    test('1. BertWordPieceTokenizer accurately encodes subword tokens and masks', () {
      final sampleVocab = [
        '[PAD]', '[unused0]', '[UNK]', '[CLS]', '[SEP]', '[MASK]',
        'a', 'cell', 'is', 'the', 'basic', 'unit', 'of', 'life', '.',
        'tree', 'photo', '##syn', '##thesis', 'emergency', 'so', '##s'
      ];
      final vocabMap = {for (int i = 0; i < sampleVocab.length; i++) sampleVocab[i]: i};
      final tokenizer = BertWordPieceTokenizer(
        vocabMap,
        unkId: 2,
        clsId: 3,
        sepId: 4,
        padId: 0,
      );

      final tokenizedTree = tokenizer.encode('tree');
      expect(tokenizedTree.inputIds, equals([3, 15, 4])); // [CLS], tree, [SEP]
      expect(tokenizedTree.attentionMask, equals([1, 1, 1]));

      final tokenizedPhoto = tokenizer.encode('photosynthesis');
      expect(tokenizedPhoto.inputIds, equals([3, 16, 17, 18, 4])); // [CLS], photo, ##syn, ##thesis, [SEP]
      expect(tokenizedPhoto.attentionMask, equals([1, 1, 1, 1, 1]));
    });

    test('2. Context Matching: "tree" contextually matches worksheet mentioning chloroplasts and plant cells', () {
      final embedder = MiniLmEmbedder();

      final plantCellText =
          'A cell is the basic unit of life. Every cell has a membrane, cytoplasm, and genetic material. '
          'The nucleus controls activities and stores DNA. Mitochondria produce energy. '
          'Plant cells also have a cell wall and chloroplasts, which animal cells lack.';
      final docVec = embedder.generateEmbedding(plantCellText);

      // Query "tree" does NOT appear anywhere in plantCellText verbatim
      final treeVec = embedder.generateEmbedding('tree');

      double cosineSim(List<double> a, List<double> b) {
        double dot = 0.0, magA = 0.0, magB = 0.0;
        for (int i = 0; i < a.length; i++) {
          dot += a[i] * b[i];
          magA += a[i] * a[i];
          magB += b[i] * b[i];
        }
        return dot / (magA * magB);
      }

      final score = cosineSim(treeVec, docVec);
      // Concept matching bridges "tree" with "chloroplasts", "plant", "photosynthesis"
      expect(score, greaterThan(0.12));

      final calibrated = LibraryService.calibrateRelevanceScore(score);
      expect(calibrated, greaterThan(0.40));
    });

    test('3. Exact keyword search receives calibrated high relevance match (88% - 99%)', () {
      final embedder = MiniLmEmbedder();
      final text = 'Mitochondria produce energy. Plant cells also have chloroplasts.';
      final docVec = embedder.generateEmbedding(text);
      final queryVec = embedder.generateEmbedding('mitochondria');

      double cosineSim(List<double> a, List<double> b) {
        double dot = 0.0;
        for (int i = 0; i < a.length; i++) {
          dot += a[i] * b[i];
        }
        return dot;
      }

      final raw = cosineSim(queryVec, docVec);
      final score = LibraryService.calibrateRelevanceScore(raw, hasExactKeyword: true);
      expect(score, greaterThanOrEqualTo(0.88));
      expect(score, lessThanOrEqualTo(0.99));
    });

    test('4. End-to-end rankDocuments handles spoken search query with semantic calibration', () async {
      final mockStore = MockEmbeddingStore();
      final library = LibraryService(mockStore);

      final cellVec = library.embedder.generateEmbedding(
        'Plant cells also have a cell wall and chloroplasts which animal cells lack.',
      );
      final sosVec = library.embedder.generateEmbedding(
        'Emergency SOS contacts and hospital hotline numbers with GPS coordinates.',
      );

      mockStore.addDocument(1, cellVec);
      mockStore.addDocument(2, sosVec);

      final results = await library.rankDocuments(
        library.embedder.generateEmbedding('tree'),
        queryText: 'tree',
        topK: 5,
      );

      expect(results, isNotEmpty);
      expect(results.first['document_id'], equals(1));
    });
  });
}

class MockEmbeddingStore extends EmbeddingStore {
  final List<Map<String, dynamic>> _storage = [];

  MockEmbeddingStore() : super(StorageService());

  void addDocument(int docId, List<double> vector) {
    _storage.add({
      'id': docId,
      'document_id': docId,
      'vector': '[${vector.join(',')}]',
    });
  }

  @override
  Future<List<Map<String, dynamic>>> fetchEmbeddings({int? limit}) async {
    return List.from(_storage);
  }
}
