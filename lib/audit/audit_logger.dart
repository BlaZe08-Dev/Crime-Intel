import 'dart:async';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/constants/constants.dart';
import '../core/security/actor_context.dart';
import '../core/utils/crypto_utils.dart';
import 'models/log_entry.dart';

/// Append-only, hash-chained audit log (`docs/Schema.md` §8).
///
/// Two invariants this class exists to hold:
///
/// 1. **Append-only.** The public surface is `log` plus reads. There is no
///    update or delete method, and none may ever be added (`docs/Rules.md` §2).
/// 2. **Attribution is enforced, not asserted.** [log] takes an [ActorContext]
///    and reads the actor off its type. Callers cannot name themselves — the
///    previous signature took a bare `LogActor` enum, which let any caller
///    claim to be the investigator.
///
/// Writes are serialised through [_writeQueue] so that `seq` stays monotonic
/// and every `prevHash` points at the entry that actually precedes it, even
/// under concurrent callers.
class AuditLogger {
  final Database _db;

  /// Tail of the write queue. Each `log` call chains onto it, so entries are
  /// appended one at a time regardless of caller concurrency.
  Future<void> _writeQueue = Future<void>.value();

  AuditLogger(this._db);

  /// Computes the entry hash defined in `docs/Schema.md` §8:
  ///
  ///     SHA256(seq | actor | action | targetType | targetId | payloadHash | ts | prevHash)
  ///
  /// The field order and separator are part of the on-disk format. Changing
  /// them invalidates every existing chain, so this must not be "tidied".
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
    final raw = '$seq|${actor.name}|${action.name}|$targetType|$targetId|'
        '$payloadHash|$ts|$prevHash';
    return CryptoUtils.sha256Hash(raw);
  }

  /// Appends an entry to the chain and returns it.
  ///
  /// [context] determines the recorded actor. The acting subject's id is folded
  /// into the payload (and therefore into `payloadHash`) so that *which*
  /// investigator acted is covered by the chain without altering the §8 hash
  /// formula.
  Future<LogEntry> log({
    required ActorContext context,
    required LogAction action,
    required String targetType,
    required String targetId,
    Map<String, dynamic>? payload,
    int? timestamp,
  }) {
    final completer = Completer<LogEntry>();

    _writeQueue = _writeQueue.then((_) async {
      try {
        final ts = timestamp ?? DateTime.now().millisecondsSinceEpoch;

        // Fold the subject into the hashed payload. Note this is the subject
        // *id*, never a credential or face embedding (`docs/Rules.md` §15).
        final effectivePayload = <String, dynamic>{
          ...?payload,
          'actorSubjectId': context.subjectId,
        };
        final payloadHash = CryptoUtils.hashPayload(effectivePayload);

        final entry = await _db.transaction((txn) async {
          final latest = await txn.query(
            'log_entries',
            orderBy: 'seq DESC',
            limit: 1,
          );

          var seq = 1;
          var prevHash = AppConstants.genesisHash;
          if (latest.isNotEmpty) {
            final previous = LogEntry.fromMap(latest.first);
            seq = previous.seq + 1;
            prevHash = previous.entryHash;
          }

          final newEntry = LogEntry(
            seq: seq,
            actor: context.actor,
            action: action,
            targetType: targetType,
            targetId: targetId,
            payloadHash: payloadHash,
            ts: ts,
            prevHash: prevHash,
            entryHash: computeEntryHash(
              seq: seq,
              actor: context.actor,
              action: action,
              targetType: targetType,
              targetId: targetId,
              payloadHash: payloadHash,
              ts: ts,
              prevHash: prevHash,
            ),
          );

          await txn.insert('log_entries', newEntry.toMap());
          return newEntry;
        });

        completer.complete(entry);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });

    return completer.future;
  }

  /// All entries, oldest first.
  Future<List<LogEntry>> getAllLogs({int? limit, int? offset}) async {
    final rows = await _db.query(
      'log_entries',
      orderBy: 'seq ASC',
      limit: limit,
      offset: offset,
    );
    return rows.map(LogEntry.fromMap).toList();
  }

  /// Most recent entries, newest first.
  Future<List<LogEntry>> getRecentLogs({int limit = 50}) async {
    final rows = await _db.query(
      'log_entries',
      orderBy: 'seq DESC',
      limit: limit,
    );
    return rows.map(LogEntry.fromMap).toList();
  }

  /// Entries touching one target, newest first — powers a record's history view.
  Future<List<LogEntry>> getLogsForTarget(String targetId,
      {int limit = 100}) async {
    final rows = await _db.query(
      'log_entries',
      where: 'targetId = ?',
      whereArgs: [targetId],
      orderBy: 'seq DESC',
      limit: limit,
    );
    return rows.map(LogEntry.fromMap).toList();
  }

  /// Total number of entries in the chain.
  Future<int> getLogCount() async {
    final result =
        await _db.rawQuery('SELECT COUNT(*) AS count FROM log_entries');
    if (result.isEmpty) return 0;
    return (result.first['count'] as num?)?.toInt() ?? 0;
  }
}
