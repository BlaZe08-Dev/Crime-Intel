import 'dart:math' as math;

import '../models/structured_records.dart';
import 'models/graph_models.dart';

/// Centrality scores for one node.
class NodeCentrality {
  final String entityId;
  final int inDegree;
  final int outDegree;

  /// Sum of weights on incident edges — how much evidence touches this node.
  final int weightedDegree;

  /// PageRank over the directed graph. High when *other* well-connected nodes
  /// point at this one, which is the right notion of "everything flows here".
  final double pageRank;

  /// Brandes betweenness over the undirected projection. High when the node
  /// sits on the paths between others — a broker or cut-out.
  final double betweenness;

  const NodeCentrality({
    required this.entityId,
    required this.inDegree,
    required this.outDegree,
    required this.weightedDegree,
    required this.pageRank,
    required this.betweenness,
  });

  int get degree => inDegree + outDegree;
}

enum AnomalySeverity { low, medium, high }

/// A flagged pattern, with the records that justify it.
class AnomalyFlag {
  final String id;
  final String kind;
  final AnomalySeverity severity;
  final String title;
  final String description;
  final List<String> evidenceIds;
  final String? subjectCriminalId;

  const AnomalyFlag({
    required this.id,
    required this.kind,
    required this.severity,
    required this.title,
    required this.description,
    required this.evidenceIds,
    this.subjectCriminalId,
  });
}

/// Full analysis over a built graph.
class GraphAnalysis {
  final Map<String, NodeCentrality> centrality;

  /// Entity id -> community index, from label propagation.
  final Map<String, int> communities;

  final List<AnomalyFlag> anomalies;

  /// Person nodes ordered most-central first. The top entry is what the UI
  /// labels the network hub.
  final List<String> rankedKeyIndividuals;

  const GraphAnalysis({
    required this.centrality,
    required this.communities,
    required this.anomalies,
    required this.rankedKeyIndividuals,
  });

  /// The most central person, or null on an empty graph.
  ///
  /// This is *computed*. If a more connected subject were added tomorrow, this
  /// would name them instead — which is exactly what the previous hardcoded
  /// `id == 'C-001'` check could not do.
  String? get hubEntityId =>
      rankedKeyIndividuals.isEmpty ? null : rankedKeyIndividuals.first;
}

/// Centrality, community detection and anomaly rules over the entity graph
/// (`docs/TechSpec.md` §2.6, `docs/PRD.md` §3.11–3.12).
class GraphAnalytics {
  /// Standard PageRank damping.
  static const double _damping = 0.85;
  static const int _pageRankIterations = 60;

  /// A transaction this many times its pair's baseline is an outlier.
  static const double _burstMultiplier = 3.0;

  /// Outliers closer together than this count as one burst.
  static const Duration _burstWindow = Duration(days: 14);

  GraphAnalysis analyse({
    required List<Entity> entities,
    required List<Edge> edges,
    required List<FinancialTxn> financial,
    required Map<String, String> criminalNames,
  }) {
    final centrality = _computeCentrality(entities, edges);
    final communities = _detectCommunities(entities, edges);

    // Rank people only. A phone or a location can be structurally central
    // without being a "key individual", and calling one a suspect would be
    // nonsense.
    final people = entities
        .where((e) => e.type == EntityType.PERSON)
        .map((e) => e.id)
        .toList();

    final ranked = people.toList()
      ..sort((a, b) {
        final byRank = (centrality[b]?.pageRank ?? 0)
            .compareTo(centrality[a]?.pageRank ?? 0);
        if (byRank != 0) return byRank;
        // Deterministic tie-break, so the hub badge never flickers between
        // equally-ranked nodes across rebuilds.
        final byDegree = (centrality[b]?.weightedDegree ?? 0)
            .compareTo(centrality[a]?.weightedDegree ?? 0);
        return byDegree != 0 ? byDegree : a.compareTo(b);
      });

    final anomalies = <AnomalyFlag>[
      ..._detectTransactionBursts(financial, criminalNames),
      ..._detectStructuralOutliers(entities, edges, centrality, criminalNames),
    ];

    return GraphAnalysis(
      centrality: centrality,
      communities: communities,
      anomalies: anomalies,
      rankedKeyIndividuals: ranked,
    );
  }

  // --- Centrality ------------------------------------------------------

  Map<String, NodeCentrality> _computeCentrality(
    List<Entity> entities,
    List<Edge> edges,
  ) {
    final ids = entities.map((e) => e.id).toList();
    final idSet = ids.toSet();
    final live = edges
        .where((e) =>
            idSet.contains(e.srcEntityId) && idSet.contains(e.dstEntityId))
        .toList();

    final inDegree = {for (final id in ids) id: 0};
    final outDegree = {for (final id in ids) id: 0};
    final weighted = {for (final id in ids) id: 0};
    final outLinks = {for (final id in ids) id: <String>[]};
    final undirected = {for (final id in ids) id: <String>{}};

    for (final edge in live) {
      outDegree[edge.srcEntityId] = outDegree[edge.srcEntityId]! + 1;
      inDegree[edge.dstEntityId] = inDegree[edge.dstEntityId]! + 1;
      weighted[edge.srcEntityId] = weighted[edge.srcEntityId]! + edge.weight;
      weighted[edge.dstEntityId] = weighted[edge.dstEntityId]! + edge.weight;
      outLinks[edge.srcEntityId]!.add(edge.dstEntityId);
      undirected[edge.srcEntityId]!.add(edge.dstEntityId);
      undirected[edge.dstEntityId]!.add(edge.srcEntityId);
    }

    final pageRank = _pageRank(ids, outLinks);
    final betweenness = _betweenness(ids, undirected);

    return {
      for (final id in ids)
        id: NodeCentrality(
          entityId: id,
          inDegree: inDegree[id]!,
          outDegree: outDegree[id]!,
          weightedDegree: weighted[id]!,
          pageRank: pageRank[id] ?? 0,
          betweenness: betweenness[id] ?? 0,
        ),
    };
  }

  Map<String, double> _pageRank(
    List<String> ids,
    Map<String, List<String>> outLinks,
  ) {
    if (ids.isEmpty) return {};
    final n = ids.length;
    var rank = {for (final id in ids) id: 1.0 / n};

    for (var iteration = 0; iteration < _pageRankIterations; iteration++) {
      final next = {for (final id in ids) id: (1 - _damping) / n};

      // Rank held by nodes with no outgoing edges is redistributed evenly
      // rather than leaking out of the system.
      var danglingMass = 0.0;
      for (final id in ids) {
        final links = outLinks[id] ?? const [];
        if (links.isEmpty) {
          danglingMass += rank[id]!;
          continue;
        }
        final share = rank[id]! / links.length;
        for (final target in links) {
          next[target] = (next[target] ?? 0) + _damping * share;
        }
      }

      final spread = _damping * danglingMass / n;
      for (final id in ids) {
        next[id] = next[id]! + spread;
      }
      rank = next;
    }

    return rank;
  }

  /// Brandes betweenness on the undirected projection, unweighted.
  Map<String, double> _betweenness(
    List<String> ids,
    Map<String, Set<String>> adjacency,
  ) {
    final score = {for (final id in ids) id: 0.0};

    for (final source in ids) {
      final stack = <String>[];
      final predecessors = {for (final id in ids) id: <String>[]};
      final sigma = {for (final id in ids) id: 0.0};
      final distance = {for (final id in ids) id: -1};

      sigma[source] = 1;
      distance[source] = 0;
      final queue = <String>[source];

      while (queue.isNotEmpty) {
        final v = queue.removeAt(0);
        stack.add(v);
        for (final w in adjacency[v] ?? const <String>{}) {
          if (distance[w] == -1) {
            distance[w] = distance[v]! + 1;
            queue.add(w);
          }
          if (distance[w] == distance[v]! + 1) {
            sigma[w] = sigma[w]! + sigma[v]!;
            predecessors[w]!.add(v);
          }
        }
      }

      final delta = {for (final id in ids) id: 0.0};
      for (final w in stack.reversed) {
        for (final v in predecessors[w]!) {
          if (sigma[w] == 0) continue;
          delta[v] = delta[v]! + (sigma[v]! / sigma[w]!) * (1 + delta[w]!);
        }
        if (w != source) score[w] = score[w]! + delta[w]!;
      }
    }

    // Undirected: each pair counted twice.
    return score.map((k, v) => MapEntry(k, v / 2));
  }

  // --- Communities -----------------------------------------------------

  /// Label propagation. Chosen over Louvain because it is a few dozen lines,
  /// needs no modularity bookkeeping, and is more than adequate at this scale.
  /// Iteration order is sorted so results are reproducible across runs.
  Map<String, int> _detectCommunities(List<Entity> entities, List<Edge> edges) {
    final ids = entities.map((e) => e.id).toList()..sort();
    if (ids.isEmpty) return {};

    final neighbours = {for (final id in ids) id: <String, int>{}};
    for (final edge in edges) {
      if (!neighbours.containsKey(edge.srcEntityId)) continue;
      if (!neighbours.containsKey(edge.dstEntityId)) continue;
      neighbours[edge.srcEntityId]!.update(
        edge.dstEntityId,
        (w) => w + edge.weight,
        ifAbsent: () => edge.weight,
      );
      neighbours[edge.dstEntityId]!.update(
        edge.srcEntityId,
        (w) => w + edge.weight,
        ifAbsent: () => edge.weight,
      );
    }

    final labels = <String, String>{for (final id in ids) id: id};

    for (var pass = 0; pass < 20; pass++) {
      var changed = false;
      for (final id in ids) {
        final adjacent = neighbours[id]!;
        if (adjacent.isEmpty) continue;

        final tally = <String, int>{};
        adjacent.forEach((neighbour, weight) {
          tally.update(labels[neighbour]!, (v) => v + weight,
              ifAbsent: () => weight);
        });

        // Highest total weight wins; ties broken by label for determinism.
        final best = tally.entries.reduce((a, b) {
          if (a.value != b.value) return a.value > b.value ? a : b;
          return a.key.compareTo(b.key) <= 0 ? a : b;
        }).key;

        if (labels[id] != best) {
          labels[id] = best;
          changed = true;
        }
      }
      if (!changed) break;
    }

    // Compact labels to small integers in a stable order.
    final order = <String, int>{};
    final result = <String, int>{};
    for (final id in ids) {
      final label = labels[id]!;
      result[id] = order.putIfAbsent(label, () => order.length);
    }
    return result;
  }

  // --- Anomalies -------------------------------------------------------

  /// Flags transaction bursts using each payer→payee pair's own baseline.
  ///
  /// Nothing here knows about C-004 or C-001. The rule is statistical: take
  /// the pair's 25th-percentile amount as its normal level, call anything at
  /// least [_burstMultiplier]× that an outlier, and report a burst when
  /// several outliers land inside [_burstWindow]. The planted spike in the
  /// synthetic data is found because it *is* an outlier, not because it was
  /// named in advance.
  ///
  /// The 25th percentile rather than the median: when roughly half a pair's
  /// transactions are the anomaly, the median is dragged up into the anomalous
  /// range and the burst hides itself.
  List<AnomalyFlag> _detectTransactionBursts(
    List<FinancialTxn> financial,
    Map<String, String> criminalNames,
  ) {
    final byPair = <String, List<FinancialTxn>>{};
    for (final txn in financial) {
      byPair.putIfAbsent('${txn.criminalId}|${txn.counterparty}', () => [])
          .add(txn);
    }

    final flags = <AnomalyFlag>[];

    byPair.forEach((pairKey, txns) {
      // Fewer than three observations is not a baseline, it is a coincidence.
      if (txns.length < 3) return;

      final amounts = txns.map((t) => t.amount).toList()..sort();
      final baseline = _percentile(amounts, 0.25);
      if (baseline <= 0) return;

      final outliers = txns
          .where((t) => t.amount >= baseline * _burstMultiplier)
          .toList()
        ..sort((a, b) => a.ts.compareTo(b.ts));
      if (outliers.isEmpty) return;

      final payerId = pairKey.split('|').first;
      final payer = criminalNames[payerId] ?? payerId;
      final payee = pairKey.split('|').last;

      final span = outliers.length < 2
          ? Duration.zero
          : Duration(milliseconds: outliers.last.ts - outliers.first.ts);
      final isBurst = outliers.length >= 2 && span <= _burstWindow;

      final total = outliers.fold<double>(0, (sum, t) => sum + t.amount);
      final peak = outliers.map((t) => t.amount).reduce(math.max);

      flags.add(AnomalyFlag(
        id: 'ANOM-TXN-$payerId-${flags.length}',
        kind: isBurst ? 'TRANSACTION_BURST' : 'TRANSACTION_OUTLIER',
        severity: isBurst ? AnomalySeverity.high : AnomalySeverity.medium,
        title: isBurst
            ? 'Transaction burst: $payer → $payee'
            : 'Outlier transaction: $payer → $payee',
        description: isBurst
            ? '${outliers.length} transfers totalling '
                '${total.toStringAsFixed(0)} within '
                '${span.inDays} days, against a baseline of '
                '${baseline.toStringAsFixed(0)} per transfer '
                '(peak ${peak.toStringAsFixed(0)}, '
                '${(peak / baseline).toStringAsFixed(1)}× baseline).'
            : 'A transfer of ${peak.toStringAsFixed(0)} against a baseline of '
                '${baseline.toStringAsFixed(0)} '
                '(${(peak / baseline).toStringAsFixed(1)}× baseline).',
        evidenceIds: outliers.map((t) => t.id).toList(),
        subjectCriminalId: payerId,
      ));
    });

    return flags;
  }

  /// Flags nodes whose connectivity is far above the rest of the network.
  List<AnomalyFlag> _detectStructuralOutliers(
    List<Entity> entities,
    List<Edge> edges,
    Map<String, NodeCentrality> centrality,
    Map<String, String> criminalNames,
  ) {
    final people =
        entities.where((e) => e.type == EntityType.PERSON).toList();
    if (people.length < 3) return const [];

    final degrees =
        people.map((p) => centrality[p.id]?.weightedDegree ?? 0).toList();
    final mean = degrees.reduce((a, b) => a + b) / degrees.length;
    final variance = degrees
            .map((d) => math.pow(d - mean, 2).toDouble())
            .reduce((a, b) => a + b) /
        degrees.length;
    final stdDev = math.sqrt(variance);
    if (stdDev == 0) return const [];

    final flags = <AnomalyFlag>[];
    for (final person in people) {
      final degree = centrality[person.id]?.weightedDegree ?? 0;
      final z = (degree - mean) / stdDev;
      if (z < 1.5) continue;

      final evidence = edges
          .where((e) =>
              e.srcEntityId == person.id || e.dstEntityId == person.id)
          .expand((e) => e.evidenceIds)
          .toSet()
          .toList()
        ..sort();

      flags.add(AnomalyFlag(
        id: 'ANOM-HUB-${person.id}',
        kind: 'CONNECTIVITY_OUTLIER',
        severity: z >= 2.0 ? AnomalySeverity.high : AnomalySeverity.medium,
        title: 'Unusual connectivity: ${person.value}',
        description:
            'Connected by $degree units of evidence, ${z.toStringAsFixed(1)} '
            'standard deviations above the network mean of '
            '${mean.toStringAsFixed(1)}.',
        evidenceIds: evidence,
        subjectCriminalId: person.id.replaceFirst('E-PERSON-', ''),
      ));
    }

    return flags;
  }

  /// Linear-interpolated percentile over a pre-sorted list.
  static double _percentile(List<double> sorted, double fraction) {
    if (sorted.isEmpty) return 0;
    if (sorted.length == 1) return sorted.first;
    final position = fraction * (sorted.length - 1);
    final lower = position.floor();
    final upper = position.ceil();
    if (lower == upper) return sorted[lower];
    return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - lower);
  }
}
