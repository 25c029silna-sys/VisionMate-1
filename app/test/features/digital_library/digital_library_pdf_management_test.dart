import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionmate/core/storage/storage_service.dart';
import 'package:visionmate/features/digital_library/data/embedding_store.dart';
import 'package:visionmate/features/digital_library/domain/library_service.dart';

class InMemoryEmbeddingStore extends EmbeddingStore {
  final List<Map<String, dynamic>> _docs = [];
  final List<Map<String, dynamic>> _embeddings = [];

  InMemoryEmbeddingStore() : super(StorageService());

  @override
  StorageService get service => _InMemoryStorageService(this);

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

class _InMemoryStorageService extends StorageService {
  final InMemoryEmbeddingStore store;
  _InMemoryStorageService(this.store);

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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Digital Library PDF Management & Deletion Tests', () {
    late InMemoryEmbeddingStore store;
    late LibraryService service;

    setUp(() {
      store = InMemoryEmbeddingStore();
      service = LibraryService(store);
    });

    test('addAndIndexDocument indexes PDF books and fetchAvailableDocuments retrieves them', () async {
      final docId1 = await service.addAndIndexDocument(
        'Grade 1 Braille Guide',
        'Braille Grade 1 is a direct character-for-character transcription of English letters.',
        sourceType: 'braille_pdf',
      );
      final docId2 = await service.addAndIndexDocument(
        'Machine Learning Textbook',
        'Supervised learning algorithms map inputs to desired output targets using training sets.',
        sourceType: 'pdf_import',
      );
      final docId3 = await service.addAndIndexDocument(
        'Voice Reminder',
        'Remember to charge white cane sensors tonight.',
        sourceType: 'user_note',
      );

      final available = await service.fetchAvailableDocuments();
      expect(available.length, 3);

      final titles = available.map((d) => d['title']).toList();
      expect(titles, contains('Grade 1 Braille Guide'));
      expect(titles, contains('Machine Learning Textbook'));
      expect(titles, contains('Voice Reminder'));

      // Verify PDF distinction
      final pdfs = available.where((d) {
        final st = (d['source_type'] as String? ?? '').toLowerCase();
        return st.contains('pdf');
      }).toList();
      expect(pdfs.length, 2);
    });

    test('deleteBook successfully removes document and associated embeddings', () async {
      final docId1 = await service.addAndIndexDocument(
        'Temporary PDF Document',
        'This document will be deleted.',
        sourceType: 'braille_pdf',
      );
      final docId2 = await service.addAndIndexDocument(
        'Permanent Guide',
        'This guide will remain.',
        sourceType: 'guide',
      );

      // Verify initially present
      expect(store._docs.length, 2);
      expect(store._embeddings.length, 2);

      // Delete the first book
      final deleted = await service.deleteBook(docId1, title: 'Temporary PDF Document');
      expect(deleted, isTrue);

      // Verify removal from database and embeddings
      expect(store._docs.length, 1);
      expect(store._docs.first['id'], docId2);
      expect(store._docs.first['title'], 'Permanent Guide');
      expect(store._embeddings.length, 1);
      expect(store._embeddings.first['document_id'], docId2);

      // Verify fetchAvailableDocuments reflects deletion
      final remaining = await service.fetchAvailableDocuments();
      expect(remaining.length, 1);
      expect(remaining.first['title'], 'Permanent Guide');
    });

    test('deleteBook returns false when deleting non-existent document ID', () async {
      final deleted = await service.deleteBook(9999, title: 'Ghost Book');
      expect(deleted, isFalse);
    });
  });
}
