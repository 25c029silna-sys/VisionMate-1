import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class StorageService {
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final path = await getDatabasesPath();
    _db = await openDatabase(
      join(path, 'visionmate.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE documents(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT,
            text TEXT,
            source_type TEXT,
            created_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE embeddings(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            document_id INTEGER,
            vector TEXT,
            FOREIGN KEY(document_id) REFERENCES documents(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE settings(
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
      },
    );
    return _db!;
  }

  Future<int> saveDocument(Map<String, dynamic> record) async {
    final db = await database;
    return db.insert('documents', record);
  }

  Future<List<Map<String, dynamic>>> fetchDocuments() async {
    final db = await database;
    return db.query('documents', orderBy: 'created_at DESC');
  }

  Future<int> deleteDocument(int id) async {
    final db = await database;
    await db.delete('embeddings', where: 'document_id = ?', whereArgs: [id]);
    return await db.delete('documents', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final results = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (results.isNotEmpty) {
      return results.first['value'] as String?;
    }
    return null;
  }

  Future<void> saveTrustedContact({required String name, required String phone}) async {
    await setSetting('trusted_contact_name', name);
    await setSetting('trusted_contact_phone', phone);
  }

  Future<Map<String, String>> getTrustedContact() async {
    try {
      final name = await getSetting('trusted_contact_name') ?? 'Emergency Contact';
      final phone = await getSetting('trusted_contact_phone') ?? '';
      return {'name': name, 'phone': phone};
    } catch (_) {
      return {'name': 'Emergency Contact', 'phone': ''};
    }
  }
}

