import '../core/config/app_config.dart';
import '../data/repositories/vector_repository.dart';
import '../llm/llm_client.dart';
import 'models/vector_chunk.dart';
import 'vector_math.dart';

/// One retrieved record, with how well it matched.
class RetrievedSource {
  final VectorChunk chunk;
  final double score;

  const RetrievedSource({required this.chunk, required this.score});

  /// The id an answer cites, e.g. `C-001`, `TXN-004`, `LOG-12`.
  String get sourceId => chunk.sourceId;

  String get sourceType => chunk.sourceType;
}

/// Outcome of a retrieval pass.
class RetrievalResult {
  final List<RetrievedSource> sources;
  final Duration duration;

  const RetrievalResult({required this.sources, required this.duration});

  /// True when nothing cleared the relevance floor.
  ///
  /// This is the signal that must produce "I don't find that in the database"
  /// rather than an answer from the model's own knowledge
  /// (`docs/Rules.md` §4, `docs/AppFlow.md` §3).
  bool get isEmpty => sources.isEmpty;

  List<String> get sourceIds =>
      sources.map((s) => s.sourceId).toList(growable: false);
}

/// Retrieval half of the RAG pipeline: question in, relevant records out.
///
/// Deliberately does no generation. Keeping retrieval separate is what lets a
/// test assert "this question retrieves TXN-004" without a model running.
class RagService {
  final VectorRepository _vectors;
  final LlmClient _llm;

  RagService({required VectorRepository vectors, required LlmClient llm})
      : _vectors = vectors,
        _llm = llm;

  /// Record identifiers as they appear in questions: `C-001`, `TXN-004`,
  /// `FIR-2023-0492`, `LOG-12`.
  static final RegExp _recordIdPattern =
      RegExp(r'\b[A-Z]{1,8}-\d[\dA-Z-]*\b', caseSensitive: false);

  /// Embeds [question] and returns the best-matching indexed records.
  ///
  /// Retrieval is **hybrid**: any record id named literally in the question is
  /// pinned into the result, and the remaining slots are filled by vector
  /// similarity.
  ///
  /// Dense retrieval alone is unreliable for exact identifiers. An imperative
  /// like "save a case note on C-001 saying he coordinates the network"
  /// embeds mostly as the *instruction*, not as C-001's profile, so cosine
  /// similarity can miss the very record the investigator named — and an empty
  /// retrieval turns into "I don't find that in the database" for a question
  /// that explicitly cited a record. Pinning exact id matches fixes that
  /// without loosening the relevance floor for everything else.
  ///
  /// [scopeCriminalId] narrows retrieval to one subject's material, for the
  /// "ask about this criminal" flow in `docs/AppFlow.md` §4.
  Future<RetrievalResult> retrieve(
    String question, {
    int? topK,
    double? minScore,
    String? scopeCriminalId,
  }) async {
    final stopwatch = Stopwatch()..start();
    final limit = topK ?? AppConfig.retrievalTopK;

    final all = await _vectors.getAll();
    if (all.isEmpty) {
      stopwatch.stop();
      return RetrievalResult(sources: const [], duration: stopwatch.elapsed);
    }

    final candidates = scopeCriminalId == null
        ? all
        : all
            .where((c) =>
                c.sourceId == scopeCriminalId ||
                c.text.contains(scopeCriminalId))
            .toList();

    if (candidates.isEmpty) {
      stopwatch.stop();
      return RetrievalResult(sources: const [], duration: stopwatch.elapsed);
    }

    // Lexical half: ids named outright in the question.
    final namedIds = _recordIdPattern
        .allMatches(question)
        .map((m) => m.group(0)!.toUpperCase())
        .toSet();

    final pinned = <RetrievedSource>[];
    final pinnedIds = <String>{};
    if (namedIds.isNotEmpty) {
      for (final chunk in candidates) {
        if (namedIds.contains(chunk.sourceId.toUpperCase()) &&
            pinnedIds.add(chunk.id)) {
          // Score 1.0: an exact id match is as relevant as retrieval gets.
          pinned.add(RetrievedSource(chunk: chunk, score: 1.0));
        }
      }
    }

    // Dense half: fill the remaining slots by similarity.
    final remaining = limit - pinned.length;
    final ranked = remaining <= 0
        ? const <ScoredItem<VectorChunk>>[]
        : VectorMath.rank<VectorChunk>(
            query: await _llm.embed(question),
            candidates:
                candidates.where((c) => !pinnedIds.contains(c.id)).toList(),
            vectorOf: (c) => c.embedding,
            topK: remaining,
            minScore: minScore ?? AppConfig.retrievalMinScore,
          );

    stopwatch.stop();
    return RetrievalResult(
      sources: [
        ...pinned,
        ...ranked.map((r) => RetrievedSource(chunk: r.item, score: r.score)),
      ],
      duration: stopwatch.elapsed,
    );
  }

  /// The exact refusal used when retrieval comes back empty.
  ///
  /// Returned verbatim without calling the model at all — a model asked to
  /// "say you don't know" will sometimes answer anyway, so the safest place to
  /// enforce grounding is before inference, not inside the prompt.
  static const String notInDatabaseAnswer =
      "I don't find that in the database.";

  /// Instructions that pin the model to the retrieved context.
  static const String systemPrompt = '''
You are CrimeIntel's investigative assistant. You answer questions about a
criminal intelligence database for a single authorised investigator.

RULES YOU MUST FOLLOW:
1. Answer ONLY from the CONTEXT RECORDS provided in the user message. They are
   the entire universe of facts available to you.
2. Never use outside or general knowledge. You have no information about the
   real world, and the people in this database are fictional.
3. Cite the bracketed record id for every fact you state, like [C-001] or
   [TXN-004]. A claim without a citation is not allowed.
4. If the CONTEXT RECORDS do not contain the answer, reply exactly:
   "I don't find that in the database."
   Do not speculate, infer beyond the records, or fill gaps.
5. Be concise and factual. This is investigative work, not prose.
6. You cannot modify records or images. If asked to, say so plainly. You may
   save a case note if the investigator asks you to.
''';

  /// Renders retrieved records into the grounded user turn.
  ///
  /// Each record keeps its bracketed id so the model can cite it and the
  /// investigator can trace every claim back to a row.
  String buildGroundedPrompt({
    required String question,
    required List<RetrievedSource> sources,
  }) {
    final buffer = StringBuffer()
      ..writeln('CONTEXT RECORDS')
      ..writeln('===============');

    for (final source in sources) {
      buffer
        ..writeln(source.chunk.text.trim())
        ..writeln('---');
    }

    buffer
      ..writeln()
      ..writeln('QUESTION')
      ..writeln('========')
      ..writeln(question.trim())
      ..writeln()
      ..writeln(
          'Answer using only the CONTEXT RECORDS above, citing record ids in '
          'brackets. If they do not contain the answer, reply exactly: '
          '"$notInDatabaseAnswer"');

    return buffer.toString();
  }
}
