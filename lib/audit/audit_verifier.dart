import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../core/constants/constants.dart';
import '../data/db/database_helper.dart';
import 'audit_logger.dart';
import 'models/log_entry.dart';

class AuditVerificationResult {
  final bool isValid;
  final int totalEntries;
  final int? brokenSeq;
  final String? errorMessage;
  final int checkedAt;

  const AuditVerificationResult({
    required this.isValid,
    required this.totalEntries,
    this.brokenSeq,
    this.errorMessage,
    required this.checkedAt,
  });

  @override
  String toString() {
    if (isValid) {
      return 'AuditVerificationResult(VALID: $totalEntries entries verified unbroken)';
    } else {
      return 'AuditVerificationResult(BROKEN at seq #$brokenSeq: $errorMessage)';
    }
  }
}

class AuditVerifier {
  final DatabaseHelper _dbHelper;
  final Database? _overrideDb;

  AuditVerifier({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _overrideDb = null;

  AuditVerifier.withDatabase(Database db)
      : _dbHelper = DatabaseHelper.instance,
        _overrideDb = db;

  Future<Database> get _db async {
    final overrideDb = _overrideDb;
    if (overrideDb != null) return overrideDb;
    return await _dbHelper.database;
  }

  /// Verifies the cryptographic integrity of the entire log chain.
  /// Recomputes each hash and verifies the pointer to the previous entry.
  Future<AuditVerificationResult> verifyChain() async {
    final db = await _db;
    final rows = await db.query(
      'log_entries',
      orderBy: 'seq ASC',
    );

    final checkedAt = DateTime.now().millisecondsSinceEpoch;

    if (rows.isEmpty) {
      return AuditVerificationResult(
        isValid: true,
        totalEntries: 0,
        checkedAt: checkedAt,
      );
    }

    final entries = rows.map((r) => LogEntry.fromMap(r)).toList();
    String expectedPrevHash = AppConstants.genesisHash;

    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final expectedSeq = i + 1;

      // 1. Check monotonic sequence
      if (entry.seq != expectedSeq) {
        return AuditVerificationResult(
          isValid: false,
          totalEntries: entries.length,
          brokenSeq: entry.seq,
          errorMessage: 'Sequence mismatch: expected #$expectedSeq, found #${entry.seq}',
          checkedAt: checkedAt,
        );
      }

      // 2. Check previous hash link
      if (entry.prevHash != expectedPrevHash) {
        return AuditVerificationResult(
          isValid: false,
          totalEntries: entries.length,
          brokenSeq: entry.seq,
          errorMessage: 'Previous hash pointer broken at seq #${entry.seq}. '
              'Expected $expectedPrevHash, got ${entry.prevHash}',
          checkedAt: checkedAt,
        );
      }

      // 3. Recompute and verify entry hash
      final computedHash = AuditLogger.computeEntryHash(
        seq: entry.seq,
        actor: entry.actor,
        action: entry.action,
        targetType: entry.targetType,
        targetId: entry.targetId,
        payloadHash: entry.payloadHash,
        ts: entry.ts,
        prevHash: entry.prevHash,
      );

      if (computedHash != entry.entryHash) {
        return AuditVerificationResult(
          isValid: false,
          totalEntries: entries.length,
          brokenSeq: entry.seq,
          errorMessage: 'Cryptographic hash tampering detected at seq #${entry.seq}. '
              'Calculated $computedHash, stored ${entry.entryHash}',
          checkedAt: checkedAt,
        );
      }

      // Move forward in the chain
      expectedPrevHash = entry.entryHash;
    }

    return AuditVerificationResult(
      isValid: true,
      totalEntries: entries.length,
      checkedAt: checkedAt,
    );
  }
}
