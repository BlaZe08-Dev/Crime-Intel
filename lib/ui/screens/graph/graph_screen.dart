import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../../../assistant/assistant_service.dart';
import '../../../core/errors/app_exceptions.dart';
import '../../../graph/graph_analytics.dart';
import '../../../graph/graph_service.dart';
import '../../../graph/models/graph_models.dart';
import '../../../main.dart';
import '../../theme/app_theme.dart';
import 'force_directed_layout.dart';

/// Network / relationship analysis (`docs/AppFlow.md` §9).
///
/// Nodes, edges, the hub highlight, the cluster colours and the anomaly list
/// are all computed by `GraphService` from the records. Nothing on this screen
/// is a fixture.
class GraphScreen extends StatefulWidget {
  const GraphScreen({super.key});

  @override
  State<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen>
    with TickerProviderStateMixin {
  NetworkSnapshot? _snapshot;
  ForceDirectedLayout? _layout;
  Ticker? _ticker;
  Size _canvas = Size.zero;
  String? _selectedId;
  bool _loading = true;
  bool _explaining = false;
  AssistantReply? _explanation;
  String? _explanationError;

  static const _communityColors = [
    WorkspaceColors.primary,
    WorkspaceColors.accentAmber,
    WorkspaceColors.accentViolet,
    WorkspaceColors.accentEmerald,
    Color(0xFFEC4899),
    Color(0xFF14B8A6),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final services = ServicesScope.of(context);
    setState(() => _loading = true);
    final snapshot = await services.graph.ensureBuilt();
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _loading = false;
    });
    _startLayout();
  }

  Future<void> _explainNetwork() async {
    final services = ServicesScope.of(context);
    setState(() {
      _explaining = true;
      _explanationError = null;
    });
    try {
      final reply = await services.assistant.explainNetwork(
        context: services.session,
      );
      if (!mounted) return;
      setState(() => _explanation = reply);
    } on AppException catch (error) {
      if (!mounted) return;
      setState(() => _explanationError = error.message);
    } finally {
      if (mounted) setState(() => _explaining = false);
    }
  }

  void _startLayout() {
    final snapshot = _snapshot;
    if (snapshot == null || _canvas == Size.zero) return;

    _ticker?.dispose();
    final layout = ForceDirectedLayout(
      entities: snapshot.entities,
      edges: snapshot.edges,
      width: _canvas.width,
      height: _canvas.height,
    );
    _layout = layout;

    // Animate the settle so the network visibly organises itself, then stop
    // the ticker - a permanently running simulation would burn CPU for a
    // picture that is no longer changing.
    _ticker = createTicker((_) {
      if (layout.isSettled) {
        _ticker?.stop();
        return;
      }
      layout.step(_canvas.width, _canvas.height);
      if (mounted) setState(() {});
    })
      ..start();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final snapshot = _snapshot;
    if (snapshot == null || snapshot.isEmpty) {
      return const Center(
        child: Text('No network could be derived from the current records.',
            style: TextStyle(color: WorkspaceColors.textSecondary)),
      );
    }

    return Row(
      children: [
        Expanded(flex: 7, child: _buildCanvas(snapshot)),
        const VerticalDivider(width: 1, color: WorkspaceColors.border),
        SizedBox(width: 340, child: _buildSidePanel(snapshot)),
      ],
    );
  }

  Widget _buildCanvas(NetworkSnapshot snapshot) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (size != _canvas) {
          _canvas = size;
          WidgetsBinding.instance.addPostFrameCallback((_) => _startLayout());
        }

        final layout = _layout;
        if (layout == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return GestureDetector(
          onTapUp: (details) {
            final hit = layout.nodeAt(details.localPosition);
            setState(() => _selectedId = hit?.id);
          },
          child: CustomPaint(
            size: size,
            painter: _NetworkPainter(
              layout: layout,
              snapshot: snapshot,
              selectedId: _selectedId,
              communityColors: _communityColors,
            ),
          ),
        );
      },
    );
  }

  Widget _buildSidePanel(NetworkSnapshot snapshot) {
    final analysis = snapshot.analysis;
    final selected = _selectedId;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Network Analysis',
            style: TextStyle(
                fontFamily: AppTheme.displayFamily,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: WorkspaceColors.textPrimary)),
        const SizedBox(height: 4),
        Text(
          '${snapshot.entities.length} entities, '
          '${snapshot.edges.length} relationships',
          style:
              const TextStyle(fontSize: 12, color: WorkspaceColors.textMuted),
        ),
        if (selected != null) ...[
          const SizedBox(height: 18),
          _sectionLabel('SELECTED NODE'),
          const SizedBox(height: 8),
          _buildSelected(snapshot, selected),
        ],
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: FilledButton.icon(
            onPressed: _explaining ? null : _explainNetwork,
            style: FilledButton.styleFrom(
                backgroundColor: WorkspaceColors.primary,
                foregroundColor: WorkspaceColors.background),
            icon: _explaining
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_outlined, size: 17),
            label: Text(_explaining
                ? 'Generating narrative...'
                : 'Explain this network'),
          ),
        ),
        if (_explanationError != null) ...[
          const SizedBox(height: 10),
          Text(_explanationError!,
              style: const TextStyle(
                  fontSize: 12, color: WorkspaceColors.accentRose)),
        ],
        if (_explanation != null) ...[
          const SizedBox(height: 12),
          _buildExplanation(_explanation!),
        ],
        const SizedBox(height: 20),
        _sectionLabel('KEY INDIVIDUALS (PAGERANK)'),
        const SizedBox(height: 8),
        for (final MapEntry(key: i, value: entityId)
            in analysis.rankedKeyIndividuals.take(5).toList().asMap().entries)
          _buildRankRow(snapshot, entityId, i + 1),
        const SizedBox(height: 20),
        _sectionLabel('FLAGGED PATTERNS'),
        const SizedBox(height: 8),
        if (analysis.anomalies.isEmpty)
          const Text('No anomalies detected.',
              style: TextStyle(fontSize: 12, color: WorkspaceColors.textMuted))
        else
          for (final anomaly in analysis.anomalies) _buildAnomaly(anomaly),
      ],
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: WorkspaceColors.textMuted,
        ),
      );

  Widget _buildExplanation(AssistantReply reply) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: WorkspaceColors.surfaceCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: WorkspaceColors.accentViolet.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('GROUNDED NARRATIVE',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: WorkspaceColors.accentViolet)),
            const SizedBox(height: 8),
            SelectableText(reply.answer,
                style: const TextStyle(
                    fontSize: 12,
                    color: WorkspaceColors.textPrimary,
                    height: 1.45)),
            if (reply.sources.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Sources: ${reply.sources.map((source) => source.sourceId).join(', ')}',
                style: AppTheme.mono
                    .copyWith(fontSize: 10, color: WorkspaceColors.primary),
              ),
            ],
          ],
        ),
      );

  Widget _buildRankRow(NetworkSnapshot snapshot, String entityId, int rank) {
    final entity = snapshot.entities.firstWhere((e) => e.id == entityId);
    final centrality = snapshot.analysis.centrality[entityId];
    final isHub = snapshot.analysis.hubEntityId == entityId;
    final pageRank = centrality?.pageRank ?? 0;

    return InkWell(
      onTap: () => setState(() => _selectedId = entityId),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: WorkspaceColors.surfaceCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isHub ? WorkspaceColors.accentAmber : WorkspaceColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    children: [
                      Text('#$rank',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: WorkspaceColors.textMuted)),
                      Text(entity.value,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: WorkspaceColors.textPrimary)),
                      if (isHub)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: WorkspaceColors.accentAmber
                                .withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('HUB',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: WorkspaceColors.accentAmber)),
                        ),
                    ],
                  ),
                ),
                Text(pageRank.toStringAsFixed(2),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: WorkspaceColors.textPrimary)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: pageRank.clamp(0, 1).toDouble(),
                minHeight: 4,
                backgroundColor: WorkspaceColors.border,
                valueColor: AlwaysStoppedAnimation(isHub
                    ? WorkspaceColors.accentAmber
                    : WorkspaceColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnomaly(AnomalyFlag anomaly) {
    final color = switch (anomaly.severity) {
      AnomalySeverity.high => WorkspaceColors.accentRose,
      AnomalySeverity.medium => WorkspaceColors.accentAmber,
      AnomalySeverity.low => WorkspaceColors.textMuted,
    };
    final severityLabel = switch (anomaly.severity) {
      AnomalySeverity.high => 'HIGH',
      AnomalySeverity.medium => 'MEDIUM',
      AnomalySeverity.low => 'LOW',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: WorkspaceColors.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: WorkspaceColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(9, 10, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(severityLabel,
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: color)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(anomaly.title,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: WorkspaceColors.textPrimary)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(anomaly.description,
                          style: const TextStyle(
                              fontSize: 11,
                              color: WorkspaceColors.textSecondary,
                              height: 1.4)),
                      const SizedBox(height: 6),
                      Text(
                        'Evidence: ${anomaly.evidenceIds.take(6).join(", ")}'
                        '${anomaly.evidenceIds.length > 6 ? " +${anomaly.evidenceIds.length - 6}" : ""}',
                        style: AppTheme.mono.copyWith(
                            fontSize: 10, color: WorkspaceColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelected(NetworkSnapshot snapshot, String entityId) {
    final matches = snapshot.entities.where((e) => e.id == entityId);
    if (matches.isEmpty) return const SizedBox.shrink();
    final entity = matches.first;
    final centrality = snapshot.analysis.centrality[entityId];
    final links = snapshot.edges
        .where((e) => e.srcEntityId == entityId || e.dstEntityId == entityId)
        .toList();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WorkspaceColors.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: WorkspaceColors.primary.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entity.value,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: WorkspaceColors.textPrimary,
                      ),
                    ),
                    Text(
                      entity.type.displayName,
                      style: const TextStyle(
                          fontSize: 11, color: WorkspaceColors.primary),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close,
                    size: 16, color: WorkspaceColors.textMuted),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Deselect',
                onPressed: () => setState(() => _selectedId = null),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Degree ${centrality?.degree ?? 0} · '
            'evidence weight ${centrality?.weightedDegree ?? 0}',
            style:
                const TextStyle(fontSize: 11, color: WorkspaceColors.textMuted),
          ),
          if (links.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final link in links.take(8))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${link.relation.displayName} · '
                  '${_otherEndLabel(snapshot, link, entityId)} '
                  '(${link.evidenceIds.length})',
                  style: const TextStyle(
                      fontSize: 11, color: WorkspaceColors.textSecondary),
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _otherEndLabel(NetworkSnapshot snapshot, Edge edge, String selfId) {
    final otherId =
        edge.srcEntityId == selfId ? edge.dstEntityId : edge.srcEntityId;
    final match = snapshot.entities.where((e) => e.id == otherId);
    return match.isEmpty ? otherId : match.first.value;
  }
}

/// Draws edges beneath nodes, sizing each node by its centrality.
class _NetworkPainter extends CustomPainter {
  final ForceDirectedLayout layout;
  final NetworkSnapshot snapshot;
  final String? selectedId;
  final List<Color> communityColors;

  _NetworkPainter({
    required this.layout,
    required this.snapshot,
    required this.selectedId,
    required this.communityColors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final byId = {for (final n in layout.nodes) n.id: n};
    final analysis = snapshot.analysis;
    final hubId = analysis.hubEntityId;

    // Edges
    for (final edge in snapshot.edges) {
      final a = byId[edge.srcEntityId];
      final b = byId[edge.dstEntityId];
      if (a == null || b == null) continue;

      final touchesSelection = selectedId != null &&
          (edge.srcEntityId == selectedId || edge.dstEntityId == selectedId);

      final paint = Paint()
        ..color = touchesSelection
            ? WorkspaceColors.primary.withValues(alpha: 0.85)
            : WorkspaceColors.border.withValues(alpha: 0.7)
        ..strokeWidth = (1.0 + (edge.weight * 0.45)).clamp(1.0, 5.0).toDouble()
        ..style = PaintingStyle.stroke;

      canvas.drawLine(a.position, b.position, paint);
    }

    // Nodes
    for (final node in layout.nodes) {
      final centrality = analysis.centrality[node.id];
      final community = analysis.communities[node.id] ?? 0;
      final color = communityColors[community % communityColors.length];
      final isHub = node.id == hubId;
      final isSelected = node.id == selectedId;

      // Size encodes evidence weight, so importance is visible at a glance.
      final double radius = node.entity.type == EntityType.PERSON
          ? (11.0 + (centrality?.weightedDegree ?? 0) * 0.6)
              .clamp(11.0, 26.0)
              .toDouble()
          : 7.0;

      if (isHub) {
        canvas.drawCircle(
          node.position,
          radius + 7,
          Paint()..color = WorkspaceColors.accentAmber.withValues(alpha: 0.22),
        );
      }

      canvas.drawCircle(
        node.position,
        radius,
        Paint()..color = color.withValues(alpha: isSelected ? 1.0 : 0.85),
      );
      canvas.drawCircle(
        node.position,
        radius,
        Paint()
          ..color = isHub
              ? WorkspaceColors.accentAmber
              : (isSelected ? Colors.white : WorkspaceColors.background)
          ..strokeWidth = isHub || isSelected ? 2.5 : 1.5
          ..style = PaintingStyle.stroke,
      );

      // Label people always; label other node types only when selected, so
      // the canvas does not turn into a wall of text.
      if (node.entity.type == EntityType.PERSON || isSelected) {
        final painter = TextPainter(
          text: TextSpan(
            text: node.entity.value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isHub ? FontWeight.w700 : FontWeight.w500,
              color: isHub
                  ? WorkspaceColors.accentAmber
                  : WorkspaceColors.textPrimary,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 130);

        painter.paint(
          canvas,
          node.position + Offset(-painter.width / 2, radius + 5),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _NetworkPainter oldDelegate) => true;
}
