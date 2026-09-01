import '../data/repositories/crime_repository.dart';
import '../data/repositories/graph_repository.dart';
import 'entity_extractor.dart';
import 'graph_analytics.dart';
import 'graph_builder.dart';
import 'models/graph_models.dart';

/// A derived graph plus its analysis, ready for display.
class NetworkSnapshot {
  final List<Entity> entities;
  final List<Edge> edges;
  final GraphAnalysis analysis;

  /// Entity id -> the criminal id it represents, for person nodes.
  final Map<String, String> personCriminalIds;

  const NetworkSnapshot({
    required this.entities,
    required this.edges,
    required this.analysis,
    required this.personCriminalIds,
  });

  static const NetworkSnapshot empty = NetworkSnapshot(
    entities: [],
    edges: [],
    analysis: GraphAnalysis(
      centrality: {},
      communities: {},
      anomalies: [],
      rankedKeyIndividuals: [],
    ),
    personCriminalIds: {},
  );

  bool get isEmpty => entities.isEmpty;

  /// Criminal id of the computed network hub, or null if there is no graph.
  String? get hubCriminalId {
    final hub = analysis.hubEntityId;
    return hub == null ? null : personCriminalIds[hub];
  }

  /// Anomaly flags that name a given criminal.
  List<AnomalyFlag> anomaliesFor(String criminalId) => analysis.anomalies
      .where((a) => a.subjectCriminalId == criminalId)
      .toList();
}

/// Owns the extract → build → analyse pipeline (`docs/AppFlow.md` §9).
///
/// The result is cached in memory because every screen wants it and the
/// computation touches the whole database. [rebuild] recomputes and persists;
/// [current] serves the cache.
class GraphService {
  final CrimeRepository _records;
  final GraphRepository _graph;
  final EntityExtractor _extractor;
  final GraphBuilder _builder;
  final GraphAnalytics _analytics;

  NetworkSnapshot? _cache;

  GraphService({
    required CrimeRepository records,
    required GraphRepository graph,
    EntityExtractor? extractor,
    GraphBuilder? builder,
    GraphAnalytics? analytics,
  })  : _records = records,
        _graph = graph,
        _extractor = extractor ?? EntityExtractor(),
        _builder = builder ?? GraphBuilder(),
        _analytics = analytics ?? GraphAnalytics();

  /// Last computed snapshot, if any.
  NetworkSnapshot? get current => _cache;

  /// Recomputes the graph from the records and persists it.
  Future<NetworkSnapshot> rebuild() async {
    final criminals = await _records.getCriminals();
    final textRecords = await _records.getAllTextRecords();
    final cdr = await _records.getAllCdr();
    final financial = await _records.getAllFinancial();

    final extraction = _extractor.extract(
      criminals: criminals,
      textRecords: textRecords,
    );

    final built = _builder.build(
      criminals: criminals,
      textRecords: textRecords,
      cdr: cdr,
      financial: financial,
      extraction: extraction,
    );

    await _graph.replaceGraph(
      entities: built.entities,
      edges: built.edges,
    );

    final analysis = _analytics.analyse(
      entities: built.entities,
      edges: built.edges,
      financial: financial,
      criminalNames: {for (final c in criminals) c.id: c.name},
    );

    final snapshot = NetworkSnapshot(
      entities: built.entities,
      edges: built.edges,
      analysis: analysis,
      personCriminalIds: {
        for (final c in criminals) 'E-PERSON-${c.id}': c.id,
      },
    );

    _cache = snapshot;
    return snapshot;
  }

  /// Returns the cached snapshot, computing one on first use.
  Future<NetworkSnapshot> ensureBuilt() async => _cache ?? await rebuild();
}
