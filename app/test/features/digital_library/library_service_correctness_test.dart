import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionmate/features/digital_library/domain/library_service.dart';
import 'package:visionmate/features/digital_library/data/embedding_store.dart';
import 'package:visionmate/core/storage/storage_service.dart';

/// In-memory test store inheriting from EmbeddingStore to test LibraryService ranking logic.
class MockEmbeddingStore extends EmbeddingStore {
  final List<Map<String, dynamic>> _storage = [];

  MockEmbeddingStore() : super(StorageService());

  void addDocument(int docId, List<double> vector) {
    _storage.add({
      'id': docId,
      'document_id': docId,
      'vector': jsonEncode(vector),
    });
  }

  @override
  Future<List<Map<String, dynamic>>> fetchEmbeddings({int? limit}) async {
    if (limit != null && limit < _storage.length) {
      return _storage.sublist(0, limit);
    }
    return List.from(_storage);
  }
}

void main() {
  group('LibraryService Correctness & Ranking Tests', () {
    test('Ensures ranking scores all documents and does NOT drop document #140 out of 150', () async {
      final mockStore = MockEmbeddingStore();
      final queryVector = [1.0, 0.0, 0.0, 0.0];

      // Populate 150 documents into store with orthogonal dummy vectors [0, 1, 0, 0]
      for (int i = 1; i <= 150; i++) {
        if (i == 140) {
          // Document #140 is the exact match for queryVector
          mockStore.addDocument(140, [1.0, 0.0, 0.0, 0.0]);
        } else {
          // Other documents have zero similarity to queryVector
          mockStore.addDocument(i, [0.0, 1.0, 0.0, 0.0]);
        }
      }

      final service = LibraryService(mockStore);

      // Perform rank search requesting top 10 results
      final results = await service.rankDocuments(queryVector, topK: 10);

      expect(results, isNotEmpty);
      expect(results.length, lessThanOrEqualTo(10));
      // Document #140 MUST be the #1 top ranked result
      expect(results.first['document_id'], equals(140));
      expect(results.first['score'], closeTo(1.0, 1e-5));
    });
  });
}
