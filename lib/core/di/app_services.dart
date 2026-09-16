import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../assistant/action_guard.dart';
import '../../auth/auth_service.dart';
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
  final AuthService auth;

  /// The acting investigator, minted only after [completeLogin] receives a
  /// verified local account identity. It is never available on the login UI.
  late InvestigatorContext session;

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
    required this.auth,
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
      auth: AuthService(db: db, audit: audit),
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

  Future<void> completeLogin(String userId) async {
    session = InvestigatorContext.issueForSession(AuthSessionIssuer.issue(
      investigatorId: userId,
      sessionId: 'SESSION-${DateTime.now().millisecondsSinceEpoch}',
    ));
    await audit.log(context: session, action: LogAction.LOGIN_OK,
        targetType: 'Account', targetId: userId, payload: {'sessionId': session.sessionId});
  }

  Future<void> dispose() async {
    llm.dispose();
    auth.dispose();
    await db.close();
  }
}
