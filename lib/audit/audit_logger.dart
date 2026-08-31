import 'dart:async';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../core/constants/constants.dart';
import '../core/utils/crypto_utils.dart';
import '../data/db/database_helper.dart';
import 'models/log_entry.dart';

class AuditLogger {
  static final AuditLogger instance = AuditLogger._init();
  final DatabaseHelper _dbHelper;
  Database? _overrideDb;

  // Lock to ensure serial execution of log writes
  final _lock = Completer<void>()..complete();
  Future<void> _lastLogFuture = Future.value();

  AuditLogger._init({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  /// Constructor for testing with an in-memory database
  AuditLogger.withDatabase(Database db)
      : _dbHelper = DatabaseHelper.instance,
        _overrideDb = db;

  Future<Database> get _db async {
    final overrideDb = _overrideDb;
    if (overrideDb != null) return overrideDb;
    return await _dbHelper.database;
  }

  /// Calculates the cryptographic SHA-256 hash for a log entry following Schema.md §8:
  /// entryHash = SHA256(seq | actor | action | targetType | targetId | payloadHash | ts | prevHash)
  static String computeEntryHash({
    required int seq,
    required LogActor actor,
    required LogAction action,
    required String targetType,
    required String targetId,
    required String payloadHash,
    required int ts,
    required String prevHash,
  }) {
    final raw = '$seq|${actor.name}|${action.name}|$targetType|$targetId|$payloadHash|$ts|$prevHash';
    return CryptoUtils.sha256Hash(raw);
  }

  /// Logs an event into the immutable, hash-chained audit log.
  /// This method is serialized to guarantee monotonic seq and unbroken prevHash pointers.
  Future<LogEntry> log({
    required LogActor actor,
    required LogAction action,
    required String targetType,
    required String targetId,
    Map<String, dynamic>? payload,
    String? rawPayloadHash,
    int? timestamp,
  }) async {
    final completer = Completer<LogEntry>();

    // Serialize log entry creation
    _lastLogFuture = _lastLogFuture.then((_) async {
      try {
        final db = await _db;
        final ts = timestamp ?? DateTime.now().millisecondsSinceEpoch;
        final payloadHash = rawPayloadHash ?? CryptoUtils.hashPayload(payload);

        final entry = await db.transaction((txn) async {
          // Find latest log entry
          final latestList = await txn.query(
            'log_entries',
            orderBy: 'seq DESC',
            limit: 1,
          );

          int seq = 1;
          String prevHash = AppConstants.genesisHash;

          if (latestList.isNotEmpty) {
            final latest = LogEntry.fromMap(latestList.first);
            seq = latest.seq + 1;
            prevHash = latest.entryHash;
          }

          final entryHash = computeEntryHash(
            seq: seq,
            actor: actor,
            action: action,
            targetType: targetType,
            targetId: targetId,
            payloadHash: payloadHash,
            ts: ts,
            prevHash: prevHash,
          );

          final newEntry = LogEntry(
            seq: seq,
            actor: actor,
            action: action,
            targetType: targetType,
            targetId: targetId,
            payloadHash: payloadHash,
            ts: ts,
            prevHash: prevHash,
            entryHash: entryHash,
          );

          await txn.insert('log_entries', newEntry.toMap());
          return newEntry;
        });

        completer.complete(entry);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });

    return completer.future;
  }

  /// Fetches all log entries in chronological order
  Future<List<LogEntry>> getAllLogs({int? limit, int? offset}) async {
    final db = await _db;
    final maps = await db.query(
      'log_entries',
      orderBy: 'seq ASC',
      limit: limit,
      offset: offset,
    );
    return maps.map((m) => LogEntry.fromMap(m)).toList();
  }

  /// Fetches recent logs
  Future<List<LogEntry>> getRecentLogs({int limit = 50}) async {
    final db = await _db;
    final maps = await db.query(
      'log_entries',
      orderBy: 'seq DESC',
      limit: limit,
    );
    return maps.map((m) => LogEntry.fromMap(m)).toList();
  }

  /// Gets the total number of log entries
  Future<int> getLogCount() async {
    final db = await _db;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM log_entries');
    if (result.isNotEmpty) {
      return (result.first['count'] as num).toInt();
    }
    return 0;
  }
}
