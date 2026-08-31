import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../audit/audit_logger.dart';
import '../audit/models/log_entry.dart';
import '../auth/models/investigator.dart';
import '../data/db/database_helper.dart';
import '../graph/models/graph_models.dart';
import '../models/case_note.dart';
import '../models/criminal.dart';
import '../models/media_item.dart';
import '../models/structured_records.dart';
import '../models/text_record.dart';
import 'seed_data.dart';

class IngestionService {
  static final IngestionService instance = IngestionService._init();
  final DatabaseHelper _dbHelper;
  final AuditLogger _auditLogger;
  Database? _overrideDb;

  IngestionService._init({DatabaseHelper? dbHelper, AuditLogger? auditLogger})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _auditLogger = auditLogger ?? AuditLogger.instance;

  IngestionService.withDatabase(Database db, AuditLogger auditLogger)
      : _dbHelper = DatabaseHelper.instance,
        _auditLogger = auditLogger,
        _overrideDb = db;

  Future<Database> get _db async {
    final overrideDb = _overrideDb;
    if (overrideDb != null) return overrideDb;
    return await _dbHelper.database;
  }

  /// Checks whether synthetic dataset is already seeded in the database
  Future<bool> isDatabaseSeeded() async {
    final db = await _db;
    final res = await db.rawQuery('SELECT COUNT(*) as count FROM criminals');
    final count = (res.first['count'] as num).toInt();
    return count > 0;
  }

  /// Ingests the initial synthetic dataset and logs the system event
  Future<void> seedDatabaseIfEmpty() async {
    final seeded = await isDatabaseSeeded();
    if (seeded) return;

    final db = await _db;

    await db.transaction((txn) async {
      // 1. Criminals
      for (final c in SeedData.criminals) {
        await txn.insert('criminals', c.toMap());
      }

      // 2. Media Items
      for (final m in SeedData.mediaItems) {
        await txn.insert('media_items', m.toMap());
      }

      // 3. CDR Records
      for (final cdr in SeedData.cdrRecords) {
        await txn.insert('cdr_records', cdr.toMap());
      }

      // 4. Financial Transactions
      for (final txnRecord in SeedData.financialTxns) {
        await txn.insert('financial_txns', txnRecord.toMap());
      }

      // 5. Criminal History
      for (final h in SeedData.criminalHistories) {
        await txn.insert('criminal_history', h.toMap());
      }

      // 6. Text Records
      for (final t in SeedData.textRecords) {
        await txn.insert('text_records', t.toMap());
      }

      // 7. Graph Entities
      for (final e in SeedData.entities) {
        await txn.insert('entities', e.toMap());
      }

      // 8. Graph Edges
      for (final edge in SeedData.edges) {
        await txn.insert('edges', edge.toMap());
      }

      // 9. Case Notes
      for (final note in SeedData.caseNotes) {
        await txn.insert('case_notes', note.toMap());
      }

      // 10. Default Investigator
      await txn.insert('investigators', SeedData.defaultInvestigator.toMap());
    });

    // Log the seed initialization event in the hash-chained audit log
    await _auditLogger.log(
      actor: LogActor.SYSTEM,
      action: LogAction.UPLOAD,
      targetType: 'Database',
      targetId: 'SYNTHETIC_SEED',
      payload: {
        'criminalsCount': SeedData.criminals.length,
        'cdrCount': SeedData.cdrRecords.length,
        'financialCount': SeedData.financialTxns.length,
        'textRecordsCount': SeedData.textRecords.length,
        'entitiesCount': SeedData.entities.length,
        'edgesCount': SeedData.edges.length,
        'note': 'Seeded synthetic intelligence network with C-001 central hub',
      },
    );
  }

  // --- Read Operations ---

  Future<List<Criminal>> getCriminals({bool includeDeleted = false}) async {
    final db = await _db;
    final where = includeDeleted ? null : 'isDeleted = 0';
    final maps = await db.query('criminals', where: where, orderBy: 'name ASC');
    return maps.map((m) => Criminal.fromMap(m)).toList();
  }

  Future<Criminal?> getCriminalById(String id) async {
    final db = await _db;
    final maps = await db.query('criminals', where: 'id = ?', whereArgs: [id], limit: 1);
    if (maps.isEmpty) return null;
    return Criminal.fromMap(maps.first);
  }

  Future<List<MediaItem>> getMediaItemsForCriminal(String criminalId) async {
    final db = await _db;
    final maps = await db.query('media_items', where: 'criminalId = ?', whereArgs: [criminalId]);
    return maps.map((m) => MediaItem.fromMap(m)).toList();
  }

  Future<List<CdrRecord>> getCdrForCriminal(String criminalId) async {
    final db = await _db;
    final maps = await db.query('cdr_records', where: 'criminalId = ?', whereArgs: [criminalId], orderBy: 'ts DESC');
    return maps.map((m) => CdrRecord.fromMap(m)).toList();
  }

  Future<List<FinancialTxn>> getFinancialTxnsForCriminal(String criminalId) async {
    final db = await _db;
    final maps = await db.query('financial_txns', where: 'criminalId = ?', whereArgs: [criminalId], orderBy: 'ts DESC');
    return maps.map((m) => FinancialTxn.fromMap(m)).toList();
  }

  Future<List<CriminalHistory>> getCriminalHistory(String criminalId) async {
    final db = await _db;
    final maps = await db.query('criminal_history', where: 'criminalId = ?', whereArgs: [criminalId], orderBy: 'date DESC');
    return maps.map((m) => CriminalHistory.fromMap(m)).toList();
  }

  Future<List<TextRecord>> getTextRecordsForCriminal(String criminalId) async {
    final db = await _db;
    final maps = await db.query('text_records', where: 'criminalId = ?', whereArgs: [criminalId], orderBy: 'createdAt DESC');
    return maps.map((m) => TextRecord.fromMap(m)).toList();
  }

  Future<List<CaseNote>> getCaseNotesForCriminal(String criminalId) async {
    final db = await _db;
    final maps = await db.query('case_notes', where: 'criminalId = ?', whereArgs: [criminalId], orderBy: 'createdAt DESC');
    return maps.map((m) => CaseNote.fromMap(m)).toList();
  }

  Future<List<Entity>> getAllEntities() async {
    final db = await _db;
    final maps = await db.query('entities');
    return maps.map((m) => Entity.fromMap(m)).toList();
  }

  Future<List<Edge>> getAllEdges() async {
    final db = await _db;
    final maps = await db.query('edges');
    return maps.map((m) => Edge.fromMap(m)).toList();
  }

  // --- Mutating Operations (All Audited) ---

  /// Soft deletes a criminal record and logs the deletion event
  Future<void> softDeleteCriminal(String criminalId, {required LogActor actor}) async {
    final db = await _db;
    final existing = await getCriminalById(criminalId);
    if (existing == null) return;

    await db.update(
      'criminals',
      {'isDeleted': 1, 'updatedAt': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [criminalId],
    );

    await _auditLogger.log(
      actor: actor,
      action: LogAction.DELETE,
      targetType: 'Criminal',
      targetId: criminalId,
      payload: {
        'previousState': existing.toMap(),
        'isSoftDeleted': true,
      },
    );
  }

  /// Adds a case note (can be investigator or assistant) and logs the event
  Future<void> addCaseNote(CaseNote note) async {
    final db = await _db;
    await db.insert('case_notes', note.toMap());

    await _auditLogger.log(
      actor: note.author == NoteAuthor.ASSISTANT ? LogActor.ASSISTANT : LogActor.INVESTIGATOR,
      action: LogAction.CREATE_CASENOTE,
      targetType: 'CaseNote',
      targetId: note.id,
      payload: note.toMap(),
    );
  }
}
