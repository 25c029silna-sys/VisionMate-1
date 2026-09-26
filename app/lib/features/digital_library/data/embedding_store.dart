import 'dart:convert';
import '../../../core/storage/storage_service.dart';

class EmbeddingStore {
  final StorageService service;
  EmbeddingStore(this.service);

  Future<int> saveEmbedding(int documentId, List<double> vector) async {
    final db = await service.database;
    return db.insert('embeddings', {
      'document_id': documentId,
      'vector': jsonEncode(vector),
    });
  }

  Future<List<Map<String, dynamic>>> fetchEmbeddings({int? limit}) async {
    final db = await service.database;
    return db.query('embeddings', limit: limit);
  }

  Future<int> deleteEmbedding(int documentId) async {
    final db = await service.database;
    return db.delete('embeddings', where: 'document_id = ?', whereArgs: [documentId]);
  }
}
