import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/constants/constants.dart';
import 'audit_logger.dart';
import 'models/log_entry.dart';

/// Outcome of a full chain verification.
class AuditVerificationResult {
  final bool isValid;
  final int totalEntries;
  final int? brokenSeq;
  final String? errorMessage;
  final int checkedAt;

  const AuditVerificationResult({
    required this.isValid,
    required this.totalEntries,
    required this.checkedAt,
    this.brokenSeq,
    this.errorMessage,
  });

  @override
  String toString() => isValid
      ? 'AuditVerificationResult(VALID: $totalEntries entries verified unbroken)'
      : 'AuditVerificationResult(BROKEN at seq #$brokenSeq: $errorMessage)';
}

/// Recomputes the audit chain from scratch to prove it has not been edited.
///
/// This is the visible tamper-evidence feature: any row that was updated,
/// removed, or reordered in SQLite breaks one of the three checks below.
class AuditVerifier {
  final Database _db;

  AuditVerifier(this._db);

  /// Walks the chain oldest-first, checking sequence continuity, the
  /// `prevHash` links, and each recomputed `entryHash`.
  Future<AuditVerificationResult> verifyChain() async {
    final rows = await _db.query('log_entries', orderBy: 'seq ASC');
    final checkedAt = DateTime.now().millisecondsSinceEpoch;

    if (rows.isEmpty) {
      return AuditVerificationResult(
        isValid: true,
        totalEntries: 0,
        checkedAt: checkedAt,
      );
    }

    final entries = rows.map(LogEntry.fromMap).toList();
    var expectedPrevHash = AppConstants.genesisHash;

    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final expectedSeq = i + 1;

      // A gap here means a row was deleted, which the schema is meant to make
      // impossible - so it is reported as tampering, not as a soft warning.
      if (entry.seq != expectedSeq) {
        return AuditVerificationResult(
          isValid: false,
          totalEntries: entries.length,
          brokenSeq: entry.seq,
          errorMessage:
              'Sequence mismatch: expected #$expectedSeq, found #${entry.seq}',
          checkedAt: checkedAt,
        );
      }

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
          errorMessage:
              'Cryptographic hash tampering detected at seq #${entry.seq}. '
              'Calculated $computedHash, stored ${entry.entryHash}',
          checkedAt: checkedAt,
        );
      }

      expectedPrevHash = entry.entryHash;
    }

    return AuditVerificationResult(
      isValid: true,
      totalEntries: entries.length,
      checkedAt: checkedAt,
    );
  }
}
