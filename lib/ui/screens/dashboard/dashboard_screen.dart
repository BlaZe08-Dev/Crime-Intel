import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../audit/audit_verifier.dart';
import '../../../audit/models/log_entry.dart';
import '../../../graph/graph_service.dart';
import '../../../main.dart';
import '../../../models/criminal.dart';
import '../../theme/app_theme.dart';
import '../criminal/criminal_detail_screen.dart';

/// Investigator dashboard (`docs/AppFlow.md` §2).
///
/// Every number and badge here is computed. The three things this screen used
/// to assert without evidence are now derived:
///
/// * the hub badge came from `criminal.id == 'C-001'`; it now comes from the
///   PageRank ranking in `GraphAnalysis`;
/// * the entity and edge tiles read hand-authored seed constants labelled
///   "Extracted Nodes"; those tables are now built by `GraphService` from the
///   records;
/// * the audit tile showed `_recentLogs.length`, capped at ten by its own
///   query; it now uses `AuditLogger.getLogCount()`.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static final _clock = DateFormat('HH:mm:ss');

  List<Criminal> _criminals = const [];
  List<LogEntry> _recentLogs = const [];
  NetworkSnapshot? _network;
  AuditVerificationResult? _verification;
  int _logCount = 0;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final services = ServicesScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final criminals = await services.records.getCriminals();
      final network = await services.graph.ensureBuilt();
      final recent = await services.audit.getRecentLogs(limit: 8);
      final total = await services.audit.getLogCount();
      final verification = await services.verifier.verifyChain();

      if (!mounted) return;
      setState(() {
        _criminals = criminals;
        _network = network;
        _recentLogs = recent;
        _logCount = total;
        _verification = verification;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _openRecord(Criminal criminal) async {
    final services = ServicesScope.of(context);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CriminalDetailScreen(
          criminalId: criminal.id,
          services: services,
        ),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text('Could not load the dashboard: $_error',
            style: const TextStyle(color: AppColors.accentRose)),
      );
    }

    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatCards(),
                const SizedBox(height: 24),
                _buildBody(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final verification = _verification;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Text('Investigator Workspace',
              style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          if (verification != null)
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: (verification.isValid
                        ? AppColors.accentEmerald
                        : AppColors.accentRose)
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: verification.isValid
                      ? AppColors.accentEmerald
                      : AppColors.accentRose,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    verification.isValid ? Icons.verified : Icons.gpp_maybe,
                    size: 15,
                    color: verification.isValid
                        ? AppColors.accentEmerald
                        : AppColors.accentRose,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    verification.isValid
                        ? 'Audit chain verified (${verification.totalEntries})'
                        : 'Chain tampering detected',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: verification.isValid
                          ? AppColors.accentEmerald
                          : AppColors.accentRose,
                    ),
                  ),
                ],
              ),
            ),
          IconButton(
            onPressed: _load,
            tooltip: 'Refresh and re-verify',
            icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCards() {
    final network = _network;
    final anomalies = network?.analysis.anomalies.length ?? 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 48) / 4;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _statCard(
              title: 'Active Profiles',
              value: '${_criminals.length}',
              subtitle: 'Synthetic records',
              icon: Icons.person_search_outlined,
              color: AppColors.primary,
              width: width,
            ),
            _statCard(
              title: 'Network Entities',
              value: '${network?.entities.length ?? 0}',
              // Honest now: these really are extracted.
              subtitle: 'Extracted from FIR/intel text',
              icon: Icons.hub_outlined,
              color: AppColors.accentAmber,
              width: width,
            ),
            _statCard(
              title: 'Relationships',
              value: '${network?.edges.length ?? 0}',
              subtitle: 'Derived from CDR, financial, co-mention',
              icon: Icons.share_outlined,
              color: AppColors.accentPurple,
              width: width,
            ),
            _statCard(
              title: 'Audit Log Entries',
              // Real total, not the length of the preview list.
              value: '$_logCount',
              subtitle: anomalies > 0
                  ? '$anomalies pattern${anomalies == 1 ? "" : "s"} flagged'
                  : 'Hash-chained, append-only',
              icon: Icons.lock_outline,
              color: AppColors.accentEmerald,
              width: width,
            ),
          ],
        );
      },
    );
  }

  Widget _statCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required double width,
  }) {
    return Container(
      width: width.clamp(210.0, 420.0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
                Text(value,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary)),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader('Criminal Network Targets', Icons.groups_outlined),
              const SizedBox(height: 12),
              for (final criminal in _criminals) _criminalCard(criminal),
            ],
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader('Recent Activity', Icons.receipt_long_outlined),
              const SizedBox(height: 12),
              _auditFeed(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String title, IconData icon) => Row(
        children: [
          Icon(icon, size: 19, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
        ],
      );

  Widget _criminalCard(Criminal criminal) {
    final network = _network;
    // Computed, not hardcoded: whoever PageRank ranks first wears the badge.
    final isHub = network?.hubCriminalId == criminal.id;
    final flags = network?.anomaliesFor(criminal.id) ?? const [];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isHub ? AppColors.accentAmber.withValues(alpha: 0.65)
                       : AppColors.border,
          width: isHub ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openRecord(criminal),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 21,
                    backgroundColor: AppColors.surfaceElevated,
                    child: Text(criminal.id,
                        style: AppTheme.mono.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(criminal.name,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary)),
                            ),
                            if (isHub) ...[
                              const SizedBox(width: 8),
                              _badge('NETWORK HUB', AppColors.accentAmber),
                            ],
                            if (flags.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              _badge('${flags.length} FLAGGED',
                                  AppColors.accentRose),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Aliases: ${criminal.aliases.join(", ")} · '
                          '${criminal.lastKnownLoc}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  _riskBadge(criminal.riskLevel),
                  const SizedBox(width: 8),
                  _chip(criminal.status.displayName),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('Known for: ${criminal.knownFor}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.bold, color: color)),
      );

  Widget _riskBadge(RiskLevel risk) {
    final color = switch (risk) {
      RiskLevel.HIGH => AppColors.accentRose,
      RiskLevel.MED => AppColors.accentAmber,
      RiskLevel.LOW => AppColors.accentEmerald,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color),
      ),
      child: Text(risk.displayName,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Widget _chip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary)),
      );

  Widget _auditFeed() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: _recentLogs.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No audit entries yet.',
                  style: TextStyle(color: AppColors.textMuted)),
            )
          : Column(
              children: [
                for (final entry in _recentLogs)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.border.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('#${entry.seq}',
                                style: AppTheme.mono.copyWith(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(entry.action.displayName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary)),
                            ),
                            Text(
                              _clock.format(DateTime
                                  .fromMillisecondsSinceEpoch(entry.ts)),
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.textMuted),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${entry.actor.displayName} · '
                          '${entry.targetType} [${entry.targetId}]',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
