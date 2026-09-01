import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../assistant/action_guard.dart';
import '../../assistant/assistant_service.dart';
import '../../audit/audit_logger.dart';
import '../../audit/audit_verifier.dart';
import '../../audit/models/log_entry.dart';
import '../../data/db/database_helper.dart';
import '../../data/repositories/crime_repository.dart';
import '../../data/repositories/graph_repository.dart';
import '../../data/repositories/vector_repository.dart';
import '../../graph/graph_service.dart';
import '../../ingest/ingestion_service.dart';
import '../../llm/llm_client.dart';
import '../../llm/ollama_client.dart';
import '../../rag/rag_indexer.dart';
import '../../rag/rag_service.dart';
import '../config/app_config.dart';
import '../security/actor_context.dart';

/// Single composition root for the app.
///
/// Replaces the `static final X.instance` singletons that were scattered
/// across the codebase, each carrying an `_overrideDb` field so tests could
/// swap the database underneath them. That pattern made dependencies
/// invisible and let a test's database leak into another test's singleton.
/// Everything is now constructed once, here, with explicit dependencies, and
/// tests build their own instance against an in-memory database.
class AppServices {
  final Database db;
  final AuditLogger audit;
  final AuditVerifier verifier;
  final CrimeRepository records;
  final VectorRepository vectors;
  final GraphRepository graphStore;
  final IngestionService ingestion;
  final LlmClient llm;
  final RagService rag;
  final RagIndexer indexer;
  final ActionGuard guard;
  final AssistantService assistant;
  final GraphService graph;

  /// The acting investigator.
  ///
  /// **Auth is not implemented yet** (Tracker Phase 2). Until face match and
  /// the OTP fallback land, the app runs as the seeded investigator and this
  /// context is minted at startup without a credential check. It is minted
  /// through the same [AuthSessionIssuer] the real flow will use, so wiring
  /// auth in later means calling [AuthSessionIssuer.issue] after a successful
  /// match instead of at boot — no other code changes.
  ///
  /// Startup deliberately does **not** write a `LOGIN_OK` entry: nobody logged
  /// in, and a log that says otherwise would be a lie in the one place the
  /// product promises not to lie.
  final InvestigatorContext session;

  AppServices._({
    required this.db,
    required this.audit,
    required this.verifier,
    required this.records,
    required this.vectors,
    required this.graphStore,
    required this.ingestion,
    required this.llm,
    required this.rag,
    required this.indexer,
    required this.guard,
    required this.assistant,
    required this.graph,
    required this.session,
  });

  /// Builds the whole object graph.
  ///
  /// Pass [database] and [llmClient] in tests; production resolves both.
  static Future<AppServices> bootstrap({
    Database? database,
    LlmClient? llmClient,
  }) async {
    await AppConfig.load();

    final db = database ?? await DatabaseHelper().open();
    final audit = AuditLogger(db);
    final records = CrimeRepository(db, audit);
    final vectors = VectorRepository(db);
    final graphStore = GraphRepository(db);
    final llm = llmClient ?? OllamaClient();

    final rag = RagService(vectors: vectors, llm: llm);
    final guard = ActionGuard(caseNotes: records, audit: audit);

    return AppServices._(
      db: db,
      audit: audit,
      verifier: AuditVerifier(db),
      records: records,
      vectors: vectors,
      graphStore: graphStore,
      ingestion: IngestionService(db: db, audit: audit),
      llm: llm,
      rag: rag,
      indexer: RagIndexer(
        records: records,
        vectors: vectors,
        audit: audit,
        llm: llm,
      ),
      guard: guard,
      assistant: AssistantService(
        rag: rag,
        llm: llm,
        guard: guard,
        audit: audit,
      ),
      graph: GraphService(records: records, graph: graphStore),
      session: InvestigatorContext.issueForSession(
        AuthSessionIssuer.issue(
          investigatorId: 'INV-001',
          sessionId: 'SESSION-${DateTime.now().millisecondsSinceEpoch}',
        ),
      ),
    );
  }

  /// Seeds the dataset and derives the graph, if needed.
  ///
  /// The RAG index is **not** built here. It needs the embedding model, which
  /// may not be pulled yet, and a failed embed must not stop the app from
  /// launching — the investigator can still browse records and read logs
  /// without chat. The chat screen builds the index on demand and reports
  /// honestly if the model is missing.
  Future<void> prepareData() async {
    await ingestion.seedIfEmpty();
    await graph.rebuild();
  }

  /// Records that this session began without authentication, so the gap is
  /// visible in the audit trail rather than implied by its absence.
  Future<void> logUnauthenticatedStart() {
    return audit.log(
      context: const SystemContext(),
      action: LogAction.UPLOAD,
      targetType: 'Session',
      targetId: session.sessionId,
      payload: {
        'note': 'Session started without authentication - auth not yet '
            'implemented (Tracker Phase 2).',
        'investigatorId': session.investigatorId,
      },
    );
  }

  Future<void> dispose() async {
    llm.dispose();
    await db.close();
  }
}
