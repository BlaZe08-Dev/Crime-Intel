import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/errors/app_exceptions.dart';
import '../../rag/models/vector_chunk.dart';

/// Persistence for the RAG index (`vector_chunks`, `docs/Schema.md` §10).
///
/// The table existed in the schema from day one but nothing ever wrote to it;
/// this is the layer that fills it. Embeddings are stored as a JSON array of
/// doubles in a TEXT column (see [VectorChunk.toMap]) — portable, and adequate
/// for a corpus this size.
class VectorRepository {
  final Database _db;

  VectorRepository(this._db);

  /// Replaces the whole index in one transaction.
  ///
  /// Rebuild-and-swap rather than incremental update: the corpus is small, and
  /// a partially-rebuilt index that silently retrieves stale records is a far
  /// worse failure than a rebuild taking a few seconds.
  Future<void> replaceAll(List<VectorChunk> chunks) async {
    try {
      await _db.transaction((txn) async {
        await txn.delete('vector_chunks');
        final batch = txn.batch();
        for (final chunk in chunks) {
          batch.insert(
            'vector_chunks',
            chunk.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      });
    } catch (error) {
      throw DataAccessException(
        'Could not write the search index.',
        cause: error,
      );
    }
  }

  /// Loads every chunk. The scan in [VectorMath.rank] runs over this.
  Future<List<VectorChunk>> getAll() async {
    try {
      final rows = await _db.query('vector_chunks');
      return rows.map(VectorChunk.fromMap).toList();
    } catch (error) {
      throw DataAccessException(
        'Could not read the search index.',
        cause: error,
      );
    }
  }

  Future<int> count() async {
    final result =
        await _db.rawQuery('SELECT COUNT(*) AS count FROM vector_chunks');
    if (result.isEmpty) return 0;
    return (result.first['count'] as num?)?.toInt() ?? 0;
  }

  Future<bool> get isEmpty async => (await count()) == 0;

  Future<void> clear() => _db.delete('vector_chunks');
}
