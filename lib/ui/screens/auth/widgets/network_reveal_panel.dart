import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// Left-hand branding panel for the sign-in screen: a static illustration of
/// a criminal network graph with call-out insight cards, framed by the
/// product headline and the records -> entities -> network -> insights
/// pipeline strip.
///
/// This mirrors the Figma "Investigator Workspace - Login" frame. The design
/// file animates the graph in over several stages; here it is rendered as
/// the settled end state (all nodes, edges and cards visible at once) since
/// this is a desktop form screen rather than a marketing animation.
class NetworkRevealPanel extends StatelessWidget {
  const NetworkRevealPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(40, 40, 40, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(),
          const SizedBox(height: 24),
          const Expanded(child: _GraphIllustration()),
          const SizedBox(height: 24),
          const _HeadlineAndPipeline(),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          child: const Icon(Icons.shield_outlined,
              color: AppColors.textPrimary, size: 22),
        ),
        const SizedBox(width: 10),
        const Text('CrimeIntel',
            style: TextStyle(
                fontFamily: AppTheme.displayFamily,
                fontWeight: FontWeight.bold,
                fontSize: 20,
                letterSpacing: -0.5,
                color: AppColors.textPrimary)),
        Expanded(
          child: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                        color: AppColors.primary, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text('04 NETWORK REVEALED',
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.mono.copyWith(
                          fontSize: 12,
                          letterSpacing: 0.6,
                          color: AppColors.textSecondary)),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('SYNTHETIC CASE DATA',
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.mono.copyWith(
                        fontSize: 11,
                        letterSpacing: 0.55,
                        color: AppColors.textSecondary)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NodeSpec {
  final double dx, dy; // fractional position within the canvas
  final double radius;
  final Color color;
  final bool glow;
  final String? label;
  final Color? labelColor;
  const _NodeSpec(this.dx, this.dy, this.radius, this.color,
      {this.glow = false, this.label, this.labelColor});
}

const _center = _NodeSpec(0.50, 0.472, 11, AppColors.primary, glow: true);

const _nodes = <_NodeSpec>[
  _NodeSpec(0.708, 0.426, 6, AppColors.accentRose,
      label: 'C-04█', labelColor: AppColors.accentRose),
  _NodeSpec(0.320, 0.250, 6, Color(0xFFA78BFA),
      label: '████ Impex', labelColor: Color(0xFFA78BFA)),
  _NodeSpec(0.660, 0.280, 6, Color(0xFFA78BFA),
      label: 'C-01█', labelColor: Color(0xFFA78BFA)),
  _NodeSpec(0.208, 0.399, 6, AppColors.textSecondary,
      label: '+91-98███', labelColor: AppColors.textSecondary),
  _NodeSpec(0.820, 0.233, 5, Color(0xFF34D399),
      label: 'Pu██-02', labelColor: AppColors.textSecondary),
  _NodeSpec(0.125, 0.528, 6, AppColors.primary,
      label: 'C-00█', labelColor: AppColors.textPrimary),
  _NodeSpec(0.445, 0.187, 5, Color(0xFF34D399)),
  _NodeSpec(0.875, 0.657, 5, AppColors.textMuted),
  _NodeSpec(0.250, 0.693, 5, AppColors.textMuted),
  _NodeSpec(0.611, 0.730, 5, AppColors.textMuted),
  _NodeSpec(0.375, 0.565, 5, Color(0xFF34D399),
      label: 'LOC-██4', labelColor: Color(0xFF34D399)),
  _NodeSpec(0.729, 0.601, 5, Color(0xFF34D399),
      label: 'Pu██', labelColor: Color(0xFF34D399)),
  _NodeSpec(0.5625, 0.178, 5, AppColors.primary),
];

/// Corner-bracket "flagged" reticle drawn around the [_nodes] rose entry.
const _reticleTarget = Offset(0.708, 0.426);

class _GraphIllustration extends StatelessWidget {
  const _GraphIllustration();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _GraphPainter(size: size)),
          ),
          for (final node in [_center, ..._nodes]) _buildNode(node),
          const Positioned(
              top: 8,
              left: 4,
              width: 220,
              child: _InsightCard(
                barColor: Color(0xFFA78BFA),
                eyebrow: 'GROUNDED ANSWER',
                title: 'Cited from 3 records',
                detail: 'FIR-003 · TXN-014 · CDR-021',
              )),
          const Positioned(
              top: 215,
              right: 8,
              width: 220,
              child: _InsightCard(
                barColor: AppColors.accentRose,
                eyebrow: 'TRANSACTION BURST',
                title: '4 transfers in 6 days',
                detail: '4.7x baseline · 1 flagged link',
              )),
          const Positioned(
              bottom: 32,
              left: 8,
              width: 220,
              child: _InsightCard(
                barColor: AppColors.accentAmber,
                eyebrow: 'NETWORK HUB',
                title: 'C-00█ ranks #1 of 14',
                detail: 'PageRank 0.28 · 5 direct links',
              )),
        ],
      );
    });
  }

  Widget _buildNode(_NodeSpec node) {
    final dot = Container(
      width: node.radius * 2,
      height: node.radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: node.color,
        boxShadow: node.glow
            ? [
                BoxShadow(
                    color: node.color.withValues(alpha: 0.55),
                    blurRadius: 18,
                    spreadRadius: 4),
              ]
            : null,
      ),
    );
    final content = node.label == null
        ? dot
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              dot,
              const SizedBox(width: 6),
              Text(node.label!,
                  style: AppTheme.mono.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: node.labelColor ?? AppColors.textPrimary)),
            ],
          );
    return Align(
      alignment: FractionalOffset(node.dx, node.dy),
      child: FractionalTranslation(
        translation: const Offset(-0.15, -0.5),
        child: content,
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  final Size size;
  const _GraphPainter({required this.size});

  Offset _p(double dx, double dy) => Offset(dx * size.width, dy * size.height);

  @override
  void paint(Canvas canvas, Size size) {
    final centerPt = _p(_center.dx, _center.dy);

    // Radar rings behind the hub node.
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final r in [26.0, 46.0, 68.0]) {
      canvas.drawCircle(centerPt, r,
          ringPaint..color = AppColors.primary.withValues(alpha: 0.12));
    }

    // Default network edges: hub-and-spoke from the prime subject.
    final edgePaint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.8)
      ..strokeWidth = 1;
    for (final node in _nodes) {
      canvas.drawLine(centerPt, _p(node.dx, node.dy), edgePaint);
    }

    // Flagged link (rose, dashed) from the hub to the flagged node.
    _drawDashedLine(canvas, centerPt, _p(_reticleTarget.dx, _reticleTarget.dy),
        AppColors.accentRose.withValues(alpha: 0.85));

    // Investigator edge: a thin trace reaching toward the sign-in panel.
    _drawDashedLine(canvas, centerPt, _p(0.97, 0.497),
        AppColors.textSecondary.withValues(alpha: 0.5));

    // Flagged-link reticle brackets.
    final target = _p(_reticleTarget.dx, _reticleTarget.dy);
    _drawReticle(canvas, target, AppColors.accentRose.withValues(alpha: 0.9));

    final label = TextPainter(
      text: TextSpan(
        text: 'LINK FLAGGED',
        style: AppTheme.mono.copyWith(
            fontSize: 8,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w700,
            color: AppColors.accentRose),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, target + const Offset(-10, 16));
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    const dashLength = 4.0, gapLength = 3.0;
    final total = (b - a).distance;
    if (total == 0) return;
    final direction = (b - a) / total;
    var travelled = 0.0;
    while (travelled < total) {
      final segmentEnd = math.min(travelled + dashLength, total);
      canvas.drawLine(
          a + direction * travelled, a + direction * segmentEnd, paint);
      travelled = segmentEnd + gapLength;
    }
  }

  void _drawReticle(Canvas canvas, Offset center, Color color) {
    const half = 13.0, arm = 4.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    for (final corner in [
      const Offset(-1, -1),
      const Offset(1, -1),
      const Offset(-1, 1),
      const Offset(1, 1),
    ]) {
      final base = center + Offset(corner.dx * half, corner.dy * half);
      canvas.drawLine(base, base - Offset(corner.dx * arm, 0), paint);
      canvas.drawLine(base, base - Offset(0, corner.dy * arm), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) =>
      oldDelegate.size != size;
}

class _InsightCard extends StatelessWidget {
  final Color barColor;
  final String eyebrow;
  final String title;
  final String detail;
  const _InsightCard({
    required this.barColor,
    required this.eyebrow,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: barColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(eyebrow,
                          style: AppTheme.mono.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.55,
                              color: barColor)),
                      const SizedBox(height: 2),
                      Text(title,
                          style: const TextStyle(
                              fontFamily: AppTheme.displayFamily,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(detail,
                          style: AppTheme.mono.copyWith(
                              fontSize: 11, color: AppColors.textSecondary)),
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
}

class _HeadlineAndPipeline extends StatelessWidget {
  const _HeadlineAndPipeline();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: const TextSpan(
            style: TextStyle(
                fontFamily: AppTheme.displayFamily,
                fontWeight: FontWeight.w600,
                fontSize: 34,
                height: 1.25,
                color: AppColors.textPrimary),
            children: [
              TextSpan(text: 'Every '),
              TextSpan(
                  text: 'connection',
                  style: TextStyle(color: AppColors.primary)),
              TextSpan(text: ' leaves a trace.'),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Text('Sign in to reveal the network behind the records.',
            style: TextStyle(fontSize: 16, color: AppColors.textSecondary)),
        const SizedBox(height: 14),
        const Divider(color: AppColors.border, height: 1),
        const SizedBox(height: 17),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      _PipelineStep(
                          icon: Icons.description_outlined, label: 'Records'),
                      _PipelineDivider(),
                      _PipelineStep(
                          icon: Icons.person_search_outlined,
                          label: 'Entities'),
                      _PipelineDivider(),
                      _PipelineStep(icon: Icons.hub_outlined, label: 'Network'),
                      _PipelineDivider(),
                      _PipelineStep(
                          icon: Icons.auto_awesome_outlined,
                          label: 'Insights',
                          active: true),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('FIRs · call records · transactions · intel reports',
                      style: AppTheme.mono
                          .copyWith(fontSize: 12, color: AppColors.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PipelineDivider extends StatelessWidget {
  const _PipelineDivider();
  @override
  Widget build(BuildContext context) => Container(
      width: 12,
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: AppColors.border);
}

class _PipelineStep extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  const _PipelineStep(
      {required this.icon, required this.label, this.active = false});

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accentAmber : AppColors.textPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(
            color: active ? AppColors.accentAmber : AppColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: AppTheme.mono.copyWith(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w500 : FontWeight.normal,
                  color: color)),
        ],
      ),
    );
  }
}
