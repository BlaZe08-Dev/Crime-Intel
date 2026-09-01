import 'package:intl/intl.dart';

import '../audit/audit_logger.dart';
import '../audit/models/log_entry.dart';
import '../core/security/actor_context.dart';
import '../core/utils/id_generator.dart';
import '../data/repositories/crime_repository.dart';
import '../data/repositories/vector_repository.dart';
import '../llm/llm_client.dart';
import 'models/vector_chunk.dart';

/// What a rebuild produced, for display and for the audit payload.
class IndexBuildResult {
  final int chunkCount;
  final int dimensions;
  final Duration duration;
  final Map<String, int> bySourceType;

  const IndexBuildResult({
    required this.chunkCount,
    required this.dimensions,
    required this.duration,
    required this.bySourceType,
  });
}

/// Builds the RAG index over the local database.
///
/// **This is retrieval, not training.** No model weights are read, written, or
/// fine-tuned anywhere in this file or anywhere else in the app. Granite stays
/// frozen; the only "learning" is that record text is embedded once into
/// `vector_chunks` so it can be looked up later and pasted into a prompt.
///
/// The corpus is every record an investigator could reasonably ask about —
/// profiles, FIR/intel text, calls, transactions, prior history, case notes —
/// plus the audit log itself, because `docs/PRD.md` §3.2 promises questions
/// answered from "the criminal database **and the audit logs**".
class RagIndexer {
  final CrimeRepository _records;
  final VectorRepository _vectors;
  final AuditLogger _audit;
  final LlmClient _llm;

  /// Embedding requests per HTTP call. Keeps payloads small enough that a
  /// slow CPU embed does not blow the request timeout.
  static const int _batchSize = 16;

  RagIndexer({
    required CrimeRepository records,
    required VectorRepository vectors,
    required AuditLogger audit,
    required LlmClient llm,
  })  : _records = records,
        _vectors = vectors,
        _audit = audit,
        _llm = llm;

  static final DateFormat _date = DateFormat('yyyy-MM-dd');
  static final NumberFormat _money = NumberFormat.decimalPattern('en_IN');

  static String _formatTs(int ms) =>
      _date.format(DateTime.fromMillisecondsSinceEpoch(ms));

  /// Rebuilds the whole index and replaces the previous one atomically.
  Future<IndexBuildResult> rebuild({required ActorContext context}) async {
    final stopwatch = Stopwatch()..start();

    final drafts = await _collectDrafts();
    final texts = drafts.map((d) => d.text).toList();

    final embeddings = <List<double>>[];
    for (var i = 0; i < texts.length; i += _batchSize) {
      final end = (i + _batchSize).clamp(0, texts.length);
      embeddings.addAll(await _llm.embedAll(texts.sublist(i, end)));
    }

    final chunks = <VectorChunk>[];
    for (var i = 0; i < drafts.length && i < embeddings.length; i++) {
      final draft = drafts[i];
      chunks.add(VectorChunk(
        id: IdGenerator.generate('VEC'),
        sourceType: draft.sourceType,
        sourceId: draft.sourceId,
        text: draft.text,
        embedding: embeddings[i],
      ));
    }

    await _vectors.replaceAll(chunks);
    stopwatch.stop();

    final bySourceType = <String, int>{};
    for (final chunk in chunks) {
      bySourceType.update(chunk.sourceType, (n) => n + 1, ifAbsent: () => 1);
    }

    final result = IndexBuildResult(
      chunkCount: chunks.length,
      dimensions: chunks.isEmpty ? 0 : chunks.first.embedding.length,
      duration: stopwatch.elapsed,
      bySourceType: bySourceType,
    );

    // Indexing rewrites derived state over the whole corpus, so it is an
    // auditable event in its own right.
    await _audit.log(
      context: context,
      action: LogAction.UPLOAD,
      targetType: 'VectorIndex',
      targetId: 'RAG_INDEX',
      payload: {
        'chunkCount': result.chunkCount,
        'dimensions': result.dimensions,
        'embedModel': _llm.embedModel,
        'durationMs': result.duration.inMilliseconds,
        'bySourceType': bySourceType,
      },
    );

    return result;
  }

  /// Collects every chunk's text before embedding, so the expensive step runs
  /// once over a known-size list.
  Future<List<_ChunkDraft>> _collectDrafts() async {
    final drafts = <_ChunkDraft>[];

    final criminals = await _records.getCriminals(includeDeleted: true);
    final nameById = {for (final c in criminals) c.id: c.name};
    String named(String id) => nameById[id] == null ? id : '$id (${nameById[id]})';

    for (final c in criminals) {
      drafts.add(_ChunkDraft(
        sourceType: 'Criminal',
        sourceId: c.id,
        text: [
          '[${c.id}] CRIMINAL PROFILE - ${c.name}',
          'Aliases: ${c.aliases.isEmpty ? "none recorded" : c.aliases.join(", ")}.',
          'Date of birth: ${c.dob}. Gender: ${c.gender}.',
          'Status: ${c.status.displayName}. Risk level: ${c.riskLevel.displayName}.',
          'Last known location: ${c.lastKnownLoc}.',
          'Known for: ${c.knownFor}.',
          if (c.isDeleted)
            'NOTE: this record has been soft-deleted by an investigator.',
        ].join('\n'),
      ));
    }

    for (final t in await _records.getAllTextRecords()) {
      drafts.add(_ChunkDraft(
        sourceType: 'TextRecord',
        sourceId: t.id,
        text: [
          '[${t.id}] ${t.kind.displayName.toUpperCase()} - ${t.title}',
          if (t.criminalId != null) 'Subject: ${named(t.criminalId!)}.',
          'Filed: ${_formatTs(t.createdAt)}.',
          '',
          t.body,
        ].join('\n'),
      ));
    }

    for (final txn in await _records.getAllFinancial()) {
      drafts.add(_ChunkDraft(
        sourceType: 'FinancialTxn',
        sourceId: txn.id,
        text: [
          '[${txn.id}] FINANCIAL TRANSACTION',
          'From: ${named(txn.criminalId)}. To: ${txn.counterparty}.',
          'Amount: ${txn.currency} ${_money.format(txn.amount)} '
              'via ${txn.channel} on ${_formatTs(txn.ts)}.',
        ].join('\n'),
      ));
    }

    for (final cdr in await _records.getAllCdr()) {
      drafts.add(_ChunkDraft(
        sourceType: 'CdrRecord',
        sourceId: cdr.id,
        text: [
          '[${cdr.id}] CALL DETAIL RECORD',
          'Subject: ${named(cdr.criminalId)}.',
          'Caller ${cdr.callerId} called ${cdr.calleeId} '
              'on ${_formatTs(cdr.ts)} for ${cdr.durationSec}s.',
          'Cell site: ${cdr.cellSite}.',
        ].join('\n'),
      ));
    }

    for (final h in await _records.getAllHistory()) {
      drafts.add(_ChunkDraft(
        sourceType: 'CriminalHistory',
        sourceId: h.id,
        text: [
          '[${h.id}] PRIOR CRIMINAL HISTORY',
          'Subject: ${named(h.criminalId)}.',
          'Offense: ${h.offense}. Date: ${h.date}.',
          'Disposition: ${h.dispositionNote}',
        ].join('\n'),
      ));
    }

    for (final note in await _records.getAllCaseNotes()) {
      drafts.add(_ChunkDraft(
        sourceType: 'CaseNote',
        sourceId: note.id,
        text: [
          '[${note.id}] CASE NOTE by ${note.author.displayName}',
          'Subject: ${named(note.criminalId)}.',
          'Written: ${_formatTs(note.createdAt)}.',
          '',
          note.text,
        ].join('\n'),
      ));
    }

    // Audit entries, so "who looked at what, and when" is answerable in chat.
    // Only the metadata is indexed - payload hashes carry no readable content
    // and embedding them would be noise.
    for (final entry in await _audit.getAllLogs(limit: 500)) {
      drafts.add(_ChunkDraft(
        sourceType: 'LogEntry',
        sourceId: 'LOG-${entry.seq}',
        text: [
          '[LOG-${entry.seq}] AUDIT LOG ENTRY',
          '${entry.actor.displayName} performed "${entry.action.displayName}" '
              'on ${entry.targetType} ${entry.targetId}',
          'at ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(entry.ts))}.',
        ].join('\n'),
      ));
    }

    return drafts;
  }
}

/// A chunk's text before it has been embedded.
class _ChunkDraft {
  final String sourceType;
  final String sourceId;
  final String text;

  const _ChunkDraft({
    required this.sourceType,
    required this.sourceId,
    required this.text,
  });
}
