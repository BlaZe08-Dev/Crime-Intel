import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../../../graph/models/graph_models.dart';

/// A node's position during layout.
class LayoutNode {
  final Entity entity;
  Offset position;
  Offset velocity;

  LayoutNode({
    required this.entity,
    required this.position,
    this.velocity = Offset.zero,
  });

  String get id => entity.id;
}

/// Fruchterman–Reingold force-directed layout.
///
/// Nodes repel each other, edges pull their endpoints together, and a cooling
/// schedule shrinks the maximum step each tick so the graph settles instead of
/// oscillating. At this size (tens of nodes) an exact O(n²) repulsion pass is
/// cheap, so there is no quadtree approximation to get wrong.
///
/// Deterministic: initial positions come from a seeded RNG, so the same graph
/// lays out the same way every run and the demo does not reshuffle itself.
class ForceDirectedLayout {
  final List<LayoutNode> nodes;
  final List<Edge> edges;

  /// Ideal edge length, derived from area per node.
  final double k;

  double _temperature;
  final double _cooling;

  ForceDirectedLayout({
    required List<Entity> entities,
    required this.edges,
    required double width,
    required double height,
    int seed = 42,
  })  : nodes = _seedPositions(entities, width, height, seed),
        k = math.sqrt((width * height) / math.max(entities.length, 1)) * 0.62,
        _temperature = width / 8,
        _cooling = 0.972;

  static List<LayoutNode> _seedPositions(
    List<Entity> entities,
    double width,
    double height,
    int seed,
  ) {
    final random = math.Random(seed);
    final centre = Offset(width / 2, height / 2);
    final radius = math.min(width, height) * 0.32;

    // Start on a jittered circle rather than uniformly at random: it avoids
    // the near-coincident pairs that produce enormous first-step repulsions.
    return [
      for (var i = 0; i < entities.length; i++)
        LayoutNode(
          entity: entities[i],
          position: centre +
              Offset(
                math.cos(2 * math.pi * i / entities.length) * radius +
                    (random.nextDouble() - 0.5) * 24,
                math.sin(2 * math.pi * i / entities.length) * radius +
                    (random.nextDouble() - 0.5) * 24,
              ),
        ),
    ];
  }

  bool get isSettled => _temperature < 0.35;

  /// Advances the simulation one step.
  void step(double width, double height) {
    if (nodes.isEmpty) return;

    final displacement = {for (final n in nodes) n.id: Offset.zero};
    final byId = {for (final n in nodes) n.id: n};

    // Repulsion, every pair.
    for (var i = 0; i < nodes.length; i++) {
      for (var j = i + 1; j < nodes.length; j++) {
        final a = nodes[i];
        final b = nodes[j];
        var delta = a.position - b.position;
        var distance = delta.distance;

        // Coincident nodes have no defined direction; nudge them apart.
        if (distance < 0.01) {
          delta = Offset(
            (i - j).toDouble().sign * 0.5 + 0.01,
            (j - i).toDouble().sign * 0.5 + 0.01,
          );
          distance = delta.distance;
        }

        final force = (k * k) / distance;
        final push = delta / distance * force;
        displacement[a.id] = displacement[a.id]! + push;
        displacement[b.id] = displacement[b.id]! - push;
      }
    }

    // Attraction along edges, scaled by weight so well-evidenced links pull
    // harder and the strongly-connected core draws together.
    for (final edge in edges) {
      final source = byId[edge.srcEntityId];
      final target = byId[edge.dstEntityId];
      if (source == null || target == null) continue;

      final delta = source.position - target.position;
      final distance = math.max(delta.distance, 0.01);
      final weightBoost = 1 + math.log(edge.weight + 1) * 0.35;
      final force = (distance * distance) / k * weightBoost;
      final pull = delta / distance * force;

      displacement[source.id] = displacement[source.id]! - pull;
      displacement[target.id] = displacement[target.id]! + pull;
    }

    // Apply, clamped by the current temperature, and keep nodes on-canvas.
    const margin = 44.0;
    for (final node in nodes) {
      final move = displacement[node.id]!;
      final distance = math.max(move.distance, 0.01);
      final limited = move / distance * math.min(distance, _temperature);

      // Gentle pull toward the centre stops disconnected nodes drifting off.
      final toCentre = Offset(width / 2, height / 2) - node.position;
      final centring = toCentre * 0.012;

      var next = node.position + limited + centring;
      next = Offset(
        next.dx.clamp(margin, math.max(margin, width - margin)),
        next.dy.clamp(margin, math.max(margin, height - margin)),
      );
      node.position = next;
    }

    _temperature *= _cooling;
  }

  /// Runs the simulation to a stable state in one go.
  void settle(double width, double height, {int maxIterations = 400}) {
    for (var i = 0; i < maxIterations && !isSettled; i++) {
      step(width, height);
    }
  }

  /// Node nearest [point] within [radius], for hit-testing taps.
  LayoutNode? nodeAt(Offset point, {double radius = 26}) {
    LayoutNode? best;
    var bestDistance = radius;
    for (final node in nodes) {
      final distance = (node.position - point).distance;
      if (distance <= bestDistance) {
        bestDistance = distance;
        best = node;
      }
    }
    return best;
  }
}
