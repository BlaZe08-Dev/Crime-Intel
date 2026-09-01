import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/errors/app_exceptions.dart';
import '../../graph/models/graph_models.dart';

/// Persistence for the derived entity graph (`entities`, `edges`).
///
/// The graph is derived state: it is recomputed from the records rather than
/// edited, so writes always replace the whole thing.
class GraphRepository {
  final Database _db;

  GraphRepository(this._db);

  Future<List<Entity>> getEntities() async {
    try {
      final rows = await _db.query('entities');
      return rows.map(Entity.fromMap).toList();
    } catch (error) {
      throw DataAccessException('Could not read graph nodes.', cause: error);
    }
  }

  Future<List<Edge>> getEdges() async {
    try {
      final rows = await _db.query('edges');
      return rows.map(Edge.fromMap).toList();
    } catch (error) {
      throw DataAccessException('Could not read graph links.', cause: error);
    }
  }

  /// Swaps in a freshly derived graph.
  ///
  /// Edges are deleted before entities because of the foreign keys from
  /// `edges` to `entities`; the reverse order trips the constraint.
  Future<void> replaceGraph({
    required List<Entity> entities,
    required List<Edge> edges,
  }) async {
    try {
      await _db.transaction((txn) async {
        await txn.delete('edges');
        await txn.delete('entities');

        final entityBatch = txn.batch();
        for (final entity in entities) {
          entityBatch.insert(
            'entities',
            entity.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await entityBatch.commit(noResult: true);

        final edgeBatch = txn.batch();
        for (final edge in edges) {
          edgeBatch.insert(
            'edges',
            edge.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await edgeBatch.commit(noResult: true);
      });
    } catch (error) {
      throw DataAccessException('Could not save the graph.', cause: error);
    }
  }

  Future<int> countEntities() async {
    final rows = await _db.rawQuery('SELECT COUNT(*) AS count FROM entities');
    return (rows.first['count'] as num?)?.toInt() ?? 0;
  }

  Future<int> countEdges() async {
    final rows = await _db.rawQuery('SELECT COUNT(*) AS count FROM edges');
    return (rows.first['count'] as num?)?.toInt() ?? 0;
  }
}
