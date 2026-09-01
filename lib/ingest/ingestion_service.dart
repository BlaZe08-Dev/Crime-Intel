import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../audit/audit_logger.dart';
import '../audit/models/log_entry.dart';
import '../core/errors/app_exceptions.dart';
import '../core/security/actor_context.dart';
import 'seed_data.dart';

/// Loads the synthetic dataset into SQLite on first run
/// (`docs/TechSpec.md` §2.8, `docs/Criminals.md`).
///
/// Scope is deliberately narrow: **records only**. It used to also seed the
/// `entities` and `edges` tables from hand-written constants, which meant the
/// "relationship graph" was a fixture rather than an analysis. Those tables
/// are now derived by `GraphService` from these records, so seeding them here
/// would just be stale data waiting to contradict the real graph.
///
/// Reads and audited mutations live in `CrimeRepository`; this class only
/// bootstraps.
class IngestionService {
  final Database _db;
  final AuditLogger _audit;

  IngestionService({required Database db, required AuditLogger audit})
      : _db = db,
        _audit = audit;

  /// True when the database already holds records.
  Future<bool> isSeeded() async {
    final rows = await _db.rawQuery('SELECT COUNT(*) AS count FROM criminals');
    return ((rows.first['count'] as num?)?.toInt() ?? 0) > 0;
  }

  /// Seeds the synthetic dataset if the database is empty. No-op afterwards.
  ///
  /// Returns true when a seed actually ran.
  Future<bool> seedIfEmpty() async {
    if (await isSeeded()) return false;

    try {
      await _db.transaction((txn) async {
        for (final criminal in SeedData.criminals) {
          await txn.insert('criminals', criminal.toMap());
        }
        for (final media in SeedData.mediaItems) {
          await txn.insert('media_items', media.toMap());
        }
        for (final call in SeedData.cdrRecords) {
          await txn.insert('cdr_records', call.toMap());
        }
        for (final txnRecord in SeedData.financialTxns) {
          await txn.insert('financial_txns', txnRecord.toMap());
        }
        for (final history in SeedData.criminalHistories) {
          await txn.insert('criminal_history', history.toMap());
        }
        for (final text in SeedData.textRecords) {
          await txn.insert('text_records', text.toMap());
        }
        for (final note in SeedData.caseNotes) {
          await txn.insert('case_notes', note.toMap());
        }
        await txn.insert('investigators', SeedData.defaultInvestigator.toMap());
      });
    } catch (error) {
      throw DataAccessException(
        'Could not load the synthetic dataset.',
        cause: error,
      );
    }

    // Seeding is a data-loading event, so it belongs in the chain like any
    // other write. SystemContext: no human performed it.
    await _audit.log(
      context: const SystemContext(),
      action: LogAction.UPLOAD,
      targetType: 'Database',
      targetId: 'SYNTHETIC_SEED',
      payload: {
        'criminalsCount': SeedData.criminals.length,
        'mediaCount': SeedData.mediaItems.length,
        'cdrCount': SeedData.cdrRecords.length,
        'financialCount': SeedData.financialTxns.length,
        'historyCount': SeedData.criminalHistories.length,
        'textRecordsCount': SeedData.textRecords.length,
        'caseNotesCount': SeedData.caseNotes.length,
        'note': 'Seeded synthetic dataset from docs/Criminals.md',
      },
    );

    return true;
  }
}
