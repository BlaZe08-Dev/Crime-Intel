import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../audit/audit_logger.dart';
import '../../audit/models/log_entry.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/security/actor_context.dart';
import '../../core/utils/id_generator.dart';
import '../../models/case_note.dart';
import '../../models/criminal.dart';
import '../../models/media_item.dart';
import '../../models/structured_records.dart';
import '../../models/text_record.dart';
import '../../news/models/news_attachment.dart';

/// The one capability the assistant is allowed to reach.
///
/// `ActionGuard` depends on **this interface only**, never on
/// [CrimeRepository]. That is the structural half of the action boundary: the
/// assistant subsystem holds a reference whose type has a single method, so
/// there is no record- or image-mutating method for it to call even by
/// mistake. The other half is [ActorContext] — the privileged mutations below
/// demand an [InvestigatorContext], which assistant-path code cannot obtain.
abstract interface class CaseNoteSink {
  /// Appends a case note and logs it under [context].
  Future<CaseNote> writeCaseNote({
    required ActorContext context,
    required String criminalId,
    required String text,
  });
}

/// Reads and audited writes over the criminal record store.
///
/// Every mutation here goes through [AuditLogger] in the same call
/// (`docs/Rules.md` §12) — there is no way to change a record without leaving
/// a chain entry.
///
/// Reads are deliberately *not* logged by default. Internal callers (the RAG
/// indexer, the graph builder) sweep every record on startup, and logging
/// those would bury the investigator's real activity in machine noise. The
/// investigator-facing "open a record" action is [openCriminalRecord], which
/// does log (`docs/PRD.md` §3.5, `docs/AppFlow.md` §4).
class CrimeRepository implements CaseNoteSink {
  final Database _db;
  final AuditLogger _audit;

  /// Optional listener called when an entity is mutated locally.
  /// Used by the sync subsystem to enqueue items into the pending sync queue.
  void Function(
    String entityType,
    String entityId,
    String operation,
    Map<String, dynamic> payload, [
    int? timestamp,
  ])? onEntityMutated;

  CrimeRepository(this._db, this._audit, {this.onEntityMutated});

  Future<T> _guard<T>(String what, Future<T> Function() body) async {
    try {
      return await body();
    } on AppException {
      rethrow;
    } catch (error) {
      throw DataAccessException('Could not $what.', cause: error);
    }
  }

  // --- Reads (unlogged; see class doc) ---

  Future<List<Criminal>> getCriminals({bool includeDeleted = false}) {
    return _guard('load criminal records', () async {
      final rows = await _db.query(
        'criminals',
        where: includeDeleted ? null : 'isDeleted = 0',
        orderBy: 'name ASC',
      );
      return rows.map(Criminal.fromMap).toList();
    });
  }

  Future<Criminal?> getCriminalById(String id) {
    return _guard('load criminal $id', () async {
      final rows = await _db.query(
        'criminals',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      return rows.isEmpty ? null : Criminal.fromMap(rows.first);
    });
  }

  Future<List<MediaItem>> getMediaFor(String criminalId, {bool includeDeleted = false}) {
    return _guard('load media', () async {
      final rows = await _db.query(
        'media_items',
        where: includeDeleted
            ? 'criminalId = ?'
            : 'criminalId = ? AND deletedAt IS NULL',
        whereArgs: [criminalId],
      );
      return rows.map(MediaItem.fromMap).toList();
    });
  }

  Future<MediaItem?> getMediaItemById(String id, {bool includeDeleted = true}) {
    return _guard('load media item $id', () async {
      final rows = await _db.query(
        'media_items',
        where: includeDeleted ? 'id = ?' : 'id = ? AND deletedAt IS NULL',
        whereArgs: [id],
        limit: 1,
      );
      return rows.isEmpty ? null : MediaItem.fromMap(rows.first);
    });
  }

  Future<List<CdrRecord>> getCdrFor(String criminalId) {
    return _guard('load call records', () async {
      final rows = await _db.query('cdr_records',
          where: 'criminalId = ?', whereArgs: [criminalId], orderBy: 'ts DESC');
      return rows.map(CdrRecord.fromMap).toList();
    });
  }

  Future<List<CdrRecord>> getAllCdr() {
    return _guard('load call records', () async {
      final rows = await _db.query('cdr_records', orderBy: 'ts ASC');
      return rows.map(CdrRecord.fromMap).toList();
    });
  }

  Future<List<FinancialTxn>> getFinancialFor(String criminalId) {
    return _guard('load transactions', () async {
      final rows = await _db.query('financial_txns',
          where: 'criminalId = ?', whereArgs: [criminalId], orderBy: 'ts DESC');
      return rows.map(FinancialTxn.fromMap).toList();
    });
  }

  Future<List<FinancialTxn>> getAllFinancial() {
    return _guard('load transactions', () async {
      final rows = await _db.query('financial_txns', orderBy: 'ts ASC');
      return rows.map(FinancialTxn.fromMap).toList();
    });
  }

  Future<List<CriminalHistory>> getHistoryFor(String criminalId) {
    return _guard('load criminal history', () async {
      final rows = await _db.query('criminal_history',
          where: 'criminalId = ?',
          whereArgs: [criminalId],
          orderBy: 'date DESC');
      return rows.map(CriminalHistory.fromMap).toList();
    });
  }

  Future<List<CriminalHistory>> getAllHistory() {
    return _guard('load criminal history', () async {
      final rows = await _db.query('criminal_history');
      return rows.map(CriminalHistory.fromMap).toList();
    });
  }

  Future<List<TextRecord>> getTextRecordsFor(String criminalId) {
    return _guard('load reports', () async {
      final rows = await _db.query('text_records',
          where: 'criminalId = ?',
          whereArgs: [criminalId],
          orderBy: 'createdAt DESC');
      return rows.map(TextRecord.fromMap).toList();
    });
  }

  Future<List<TextRecord>> getAllTextRecords() {
    return _guard('load reports', () async {
      final rows = await _db.query('text_records', orderBy: 'createdAt ASC');
      return rows.map(TextRecord.fromMap).toList();
    });
  }

  Future<List<CaseNote>> getCaseNotesFor(String criminalId) {
    return _guard('load case notes', () async {
      final rows = await _db.query('case_notes',
          where: 'criminalId = ?',
          whereArgs: [criminalId],
          orderBy: 'createdAt DESC');
      return rows.map(CaseNote.fromMap).toList();
    });
  }

  Future<List<CaseNote>> getAllCaseNotes() {
    return _guard('load case notes', () async {
      final rows = await _db.query('case_notes', orderBy: 'createdAt ASC');
      return rows.map(CaseNote.fromMap).toList();
    });
  }

  Future<List<NewsAttachment>> getNewsFor(String criminalId) {
    return _guard('load attached news', () async {
      final rows = await _db.query('news_attachments',
          where: 'criminalId = ?',
          whereArgs: [criminalId],
          orderBy: 'createdAt DESC');
      return rows.map(NewsAttachment.fromMap).toList();
    });
  }

  // --- Investigator-facing read that is logged ---

  /// Opens a record on the investigator's behalf, logging `VIEW_RECORD`.
  ///
  /// Requires an [InvestigatorContext] rather than any [ActorContext]: a
  /// "record viewed by the investigator" entry must mean a human actually
  /// opened it (`docs/AppFlow.md` §4).
  Future<Criminal?> openCriminalRecord({
    required InvestigatorContext context,
    required String criminalId,
  }) async {
    final criminal = await getCriminalById(criminalId);
    await _audit.log(
      context: context,
      action: LogAction.VIEW_RECORD,
      targetType: 'Criminal',
      targetId: criminalId,
      payload: {
        'found': criminal != null,
        if (criminal != null) 'name': criminal.name,
      },
    );
    return criminal;
  }

  // --- Case notes: the one write the assistant can reach ---

  @override
  Future<CaseNote> writeCaseNote({
    required ActorContext context,
    required String criminalId,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const DataAccessException('A case note cannot be empty.');
    }

    final target = await getCriminalById(criminalId);
    if (target == null) {
      throw DataAccessException(
        'No criminal record with id "$criminalId" exists.',
      );
    }

    final note = CaseNote(
      id: IdGenerator.generate('NOTE'),
      criminalId: criminalId,
      // Authorship follows the context type, so an assistant-written note can
      // never be filed as investigator-authored.
      author: context is AssistantContext
          ? NoteAuthor.ASSISTANT
          : NoteAuthor.INVESTIGATOR,
      text: trimmed,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    return _guard('save the case note', () async {
      await _db.insert('case_notes', note.toMap());
      await _audit.log(
        context: context,
        action: LogAction.CREATE_CASENOTE,
        targetType: 'CaseNote',
        targetId: note.id,
        payload: note.toMap(),
      );
      onEntityMutated?.call(
        'case_note',
        note.id,
        'UPSERT',
        note.toMap(),
        note.createdAt,
      );
      return note;
    });
  }

  // --- Investigator-only mutations ---
  //
  // Each takes InvestigatorContext, not ActorContext. That is what makes the
  // assistant boundary a compile-time guarantee: assistant-path code holds an
  // AssistantContext and cannot produce an InvestigatorContext, so these calls
  // do not type-check for it.

  /// Updates mutable fields on a record, logging the prior state.
  Future<Criminal> updateCriminal({
    required InvestigatorContext context,
    required String criminalId,
    String? status,
    String? riskLevel,
    String? lastKnownLoc,
    String? knownFor,
  }) async {
    final existing = await getCriminalById(criminalId);
    if (existing == null) {
      throw DataAccessException('No criminal record with id "$criminalId".');
    }

    final updated = existing.copyWith(
      status: status == null ? null : CriminalStatus.fromString(status),
      riskLevel: riskLevel == null ? null : RiskLevel.fromString(riskLevel),
      lastKnownLoc: lastKnownLoc,
      knownFor: knownFor,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    return _guard('update the record', () async {
      await _db.update(
        'criminals',
        updated.toMap(),
        where: 'id = ?',
        whereArgs: [criminalId],
      );
      await _audit.log(
        context: context,
        action: LogAction.UPDATE,
        targetType: 'Criminal',
        targetId: criminalId,
        // Prior state is retained in the chain, so an update is reversible
        // evidence rather than a silent overwrite (`docs/Rules.md` §2).
        payload: {
          'previousState': existing.toMap(),
          'newState': updated.toMap(),
        },
      );
      onEntityMutated?.call(
        'criminal',
        updated.id,
        'UPSERT',
        updated.toMap(),
        updated.updatedAt,
      );
      return updated;
    });
  }

  /// Soft-deletes a record. There is no hard delete anywhere in the app.
  Future<void> softDeleteCriminal({
    required InvestigatorContext context,
    required String criminalId,
  }) async {
    final existing = await getCriminalById(criminalId);
    if (existing == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    await _guard('delete the record', () async {
      await _db.update(
        'criminals',
        {
          'isDeleted': 1,
          'updatedAt': now,
        },
        where: 'id = ?',
        whereArgs: [criminalId],
      );
      await _audit.log(
        context: context,
        action: LogAction.DELETE,
        targetType: 'Criminal',
        targetId: criminalId,
        payload: {
          'previousState': existing.toMap(),
          'isSoftDeleted': true,
        },
      );
      onEntityMutated?.call(
        'criminal',
        criminalId,
        'UPSERT',
        {
          ...existing.toMap(),
          'isDeleted': 1,
          'updatedAt': now,
        },
        now,
      );
    });
  }

  /// Registers an uploaded media item.
  Future<MediaItem> addMedia({
    required InvestigatorContext context,
    required MediaItem item,
  }) async {
    final toSave = item.uploadedByInvestigatorId == 'system'
        ? item.copyWith(uploadedByInvestigatorId: context.investigatorId)
        : item;
    return _guard('save the image', () async {
      await _db.insert('media_items', toSave.toMap());
      await _audit.log(
        context: context,
        action: LogAction.UPLOAD,
        targetType: 'MediaItem',
        targetId: toSave.id,
        payload: toSave.toMap(),
      );
      onEntityMutated?.call(
        'media_item',
        toSave.id,
        'UPSERT',
        toSave.toMap(),
        toSave.createdAt,
      );
      return toSave;
    });
  }

  /// Soft-deletes an uploaded media item.
  ///
  /// Restricted strictly to the investigator who uploaded it.
  /// A delete attempt by any other investigator is rejected and logged as an unauthorized action.
  Future<void> deleteMedia({
    required InvestigatorContext context,
    required String mediaId,
  }) async {
    final item = await getMediaItemById(mediaId, includeDeleted: true);
    if (item == null) {
      throw DataAccessException('Media item $mediaId does not exist.');
    }
    if (item.isDeleted) {
      return; // Already soft-deleted
    }

    if (item.uploadedByInvestigatorId != context.investigatorId) {
      await _audit.log(
        context: context,
        action: LogAction.DELETE,
        targetType: 'MediaItem',
        targetId: mediaId,
        payload: {
          'outcome': 'DENIED',
          'reason': 'Only the uploading investigator can delete this media item.',
          'attemptedBy': context.investigatorId,
          'uploadedBy': item.uploadedByInvestigatorId,
        },
      );
      throw ActionNotPermittedException(
        'deleteMedia',
        'Investigator ${context.investigatorId} is not permitted to delete media uploaded by ${item.uploadedByInvestigatorId}.',
      );
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    await _guard('soft-delete media item', () async {
      await _db.update(
        'media_items',
        {'deletedAt': now},
        where: 'id = ?',
        whereArgs: [mediaId],
      );
      await _audit.log(
        context: context,
        action: LogAction.DELETE,
        targetType: 'MediaItem',
        targetId: mediaId,
        payload: {
          'outcome': 'SOFT_DELETED',
          'previousState': item.toMap(),
          'deletedAt': now,
        },
      );
      onEntityMutated?.call(
        'media_item',
        mediaId,
        'DELETE',
        {
          ...item.toMap(),
          'deletedAt': now,
        },
        now,
      );
    });
  }

  /// Attaches a news article to a record.
  ///
  /// Investigator-gated on purpose: the assistant may *propose* an article,
  /// but only the human commits it (`docs/AppFlow.md` §6).
  Future<NewsAttachment> attachNews({
    required InvestigatorContext context,
    required NewsAttachment attachment,
  }) async {
    return _guard('attach the article', () async {
      await _db.insert('news_attachments', attachment.toMap());
      await _audit.log(
        context: context,
        action: LogAction.ATTACH_NEWS,
        targetType: 'NewsAttachment',
        targetId: attachment.id,
        payload: attachment.toMap(),
      );
      onEntityMutated?.call(
        'news_attachment',
        attachment.id,
        'UPSERT',
        attachment.toMap(),
        attachment.createdAt,
      );
      return attachment;
    });
  }

  /// Adds a new criminal record (investigator-gated).
  Future<Criminal> addCriminal({
    required InvestigatorContext context,
    required Criminal criminal,
  }) async {
    return _guard('create the criminal profile', () async {
      await _db.insert('criminals', criminal.toMap());
      await _audit.log(
        context: context,
        action: LogAction.UPLOAD,
        targetType: 'Criminal',
        targetId: criminal.id,
        payload: criminal.toMap(),
      );
      onEntityMutated?.call(
        'criminal',
        criminal.id,
        'UPSERT',
        criminal.toMap(),
        criminal.createdAt,
      );
      return criminal;
    });
  }

  /// Adds an unstructured intelligence report / FIR (investigator-gated).
  Future<TextRecord> addTextRecord({
    required InvestigatorContext context,
    required TextRecord record,
  }) async {
    return _guard('save text record', () async {
      await _db.insert('text_records', record.toMap());
      await _audit.log(
        context: context,
        action: LogAction.UPLOAD,
        targetType: 'TextRecord',
        targetId: record.id,
        payload: record.toMap(),
      );
      onEntityMutated?.call(
        'text_record',
        record.id,
        'UPSERT',
        record.toMap(),
        record.createdAt,
      );
      return record;
    });
  }

  /// Adds a call detail record (investigator-gated).
  Future<CdrRecord> addCdrRecord({
    required InvestigatorContext context,
    required CdrRecord record,
  }) async {
    return _guard('save call record', () async {
      await _db.insert('cdr_records', record.toMap());
      await _audit.log(
        context: context,
        action: LogAction.UPLOAD,
        targetType: 'CdrRecord',
        targetId: record.id,
        payload: record.toMap(),
      );
      onEntityMutated?.call(
        'cdr_record',
        record.id,
        'UPSERT',
        record.toMap(),
        record.ts,
      );
      return record;
    });
  }

  /// Adds a financial transaction (investigator-gated).
  Future<FinancialTxn> addFinancialTxn({
    required InvestigatorContext context,
    required FinancialTxn txn,
  }) async {
    return _guard('save financial transaction', () async {
      await _db.insert('financial_txns', txn.toMap());
      await _audit.log(
        context: context,
        action: LogAction.UPLOAD,
        targetType: 'FinancialTxn',
        targetId: txn.id,
        payload: txn.toMap(),
      );
      onEntityMutated?.call(
        'financial_txn',
        txn.id,
        'UPSERT',
        txn.toMap(),
        txn.ts,
      );
      return txn;
    });
  }

  /// Adds a criminal history record (investigator-gated).
  Future<CriminalHistory> addCriminalHistory({
    required InvestigatorContext context,
    required CriminalHistory history,
  }) async {
    return _guard('save criminal history', () async {
      await _db.insert('criminal_history', history.toMap());
      await _audit.log(
        context: context,
        action: LogAction.UPLOAD,
        targetType: 'CriminalHistory',
        targetId: history.id,
        payload: history.toMap(),
      );
      onEntityMutated?.call(
        'criminal_history',
        history.id,
        'UPSERT',
        history.toMap(),
        DateTime.now().millisecondsSinceEpoch,
      );
      return history;
    });
  }
}
