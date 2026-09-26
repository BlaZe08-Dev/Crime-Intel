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
            style: const TextStyle(color: WorkspaceColors.accentRose)),
      );
    }

    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
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
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: WorkspaceColors.border)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Investigator Workspace',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: WorkspaceColors.textPrimary, fontSize: 24)),
              const SizedBox(height: 2),
              const Text(
                  'Synthetic case data // Operational link-analysis environment',
                  style: TextStyle(
                      fontSize: 12, color: WorkspaceColors.textSecondary)),
            ],
          ),
          const Spacer(),
          if (verification != null)
            Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: (verification.isValid
                        ? WorkspaceColors.accentEmerald
                        : WorkspaceColors.accentRose)
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: verification.isValid
                      ? WorkspaceColors.accentEmerald
                      : WorkspaceColors.accentRose,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    verification.isValid ? Icons.verified : Icons.gpp_maybe,
                    size: 15,
                    color: verification.isValid
                        ? WorkspaceColors.accentEmerald
                        : WorkspaceColors.accentRose,
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
                          ? WorkspaceColors.accentEmerald
                          : WorkspaceColors.accentRose,
                    ),
                  ),
                ],
              ),
            ),
          IconButton(
            onPressed: _load,
            tooltip: 'Refresh and re-verify',
            icon:
                const Icon(Icons.refresh, color: WorkspaceColors.textSecondary),
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
              color: WorkspaceColors.primary,
              width: width,
            ),
            _statCard(
              title: 'Network Entities',
              value: '${network?.entities.length ?? 0}',
              // Honest now: these really are extracted.
              subtitle: 'Extracted from FIR/intel text',
              icon: Icons.hub_outlined,
              color: WorkspaceColors.accentAmber,
              width: width,
            ),
            _statCard(
              title: 'Relationships',
              value: '${network?.edges.length ?? 0}',
              subtitle: 'Derived from CDR, financial, co-mention',
              icon: Icons.share_outlined,
              color: WorkspaceColors.accentViolet,
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
              color: WorkspaceColors.accentEmerald,
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
        color: WorkspaceColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WorkspaceColors.border),
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
                        fontSize: 12, color: WorkspaceColors.textSecondary)),
                Text(value,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: WorkspaceColors.textPrimary)),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, color: WorkspaceColors.textMuted)),
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
          flex: 7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader(
                'Criminal Network Targets',
                '${_criminals.length} primary subjects tracked',
                trailing: OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.filter_alt_outlined, size: 14),
                  label: const Text('Filter Targets'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: WorkspaceColors.textPrimary,
                    side: const BorderSide(color: WorkspaceColors.border),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              for (final criminal in _criminals) _criminalCard(criminal),
            ],
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader(
                'Recent Activity',
                'Live immutable audit stream',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                          color: WorkspaceColors.accentEmerald,
                          shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text('APPEND ONLY',
                        style: AppTheme.mono.copyWith(
                            fontSize: 11, color: WorkspaceColors.textMuted)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _auditFeed(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String title, String subtitle, {Widget? trailing}) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontFamily: AppTheme.displayFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: WorkspaceColors.textPrimary)),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: WorkspaceColors.textMuted)),
              ],
            ),
          ),
          if (trailing != null) trailing,
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
          color: isHub
              ? WorkspaceColors.accentAmber.withValues(alpha: 0.65)
              : WorkspaceColors.border,
          width: isHub ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openRecord(criminal),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: WorkspaceColors.inputBackground,
                            border: Border.all(color: WorkspaceColors.border),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(criminal.id,
                              style: AppTheme.mono.copyWith(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: WorkspaceColors.textSecondary)),
                        ),
                        Text(criminal.name,
                            style: const TextStyle(
                                fontFamily: AppTheme.displayFamily,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: WorkspaceColors.textPrimary)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      _riskBadge(criminal.riskLevel),
                      _statusBadge(criminal.status),
                      if (isHub) _hubBadge(),
                      if (flags.isNotEmpty)
                        _badge('${flags.length} FLAGGED',
                            WorkspaceColors.accentRose),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(
                  style: const TextStyle(
                      fontSize: 12, color: WorkspaceColors.textMuted),
                  children: [
                    const TextSpan(text: 'Aliases: '),
                    TextSpan(
                        text: criminal.aliases.join(", "),
                        style: const TextStyle(
                            color: WorkspaceColors.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: WorkspaceColors.textSecondary),
                  children: [
                    const TextSpan(text: 'Known for: '),
                    TextSpan(
                        text: criminal.knownFor,
                        style: const TextStyle(
                            fontWeight: FontWeight.normal,
                            color: WorkspaceColors.textMuted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, Color color, {IconData? icon}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 10, color: color),
              const SizedBox(width: 4),
            ],
            Text(text,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w500, color: color)),
          ],
        ),
      );

  Widget _riskBadge(RiskLevel risk) {
    final color = switch (risk) {
      RiskLevel.HIGH => WorkspaceColors.accentRose,
      RiskLevel.MED => WorkspaceColors.accentAmber,
      RiskLevel.LOW => WorkspaceColors.accentEmerald,
    };
    return _badge(risk.displayName, color);
  }

  Widget _statusBadge(CriminalStatus status) {
    final color = switch (status) {
      CriminalStatus.AT_LARGE => WorkspaceColors.accentRose,
      CriminalStatus.IN_CUSTODY => WorkspaceColors.accentEmerald,
      CriminalStatus.UNDER_WATCH => WorkspaceColors.textSecondary,
      CriminalStatus.DECEASED => WorkspaceColors.textMuted,
    };
    return _badge(status.displayName, color);
  }

  Widget _hubBadge() =>
      _badge('NETWORK HUB', WorkspaceColors.accentAmber, icon: Icons.bolt);

  Color _actionColor(LogAction action) {
    switch (action) {
      case LogAction.LLM_QUERY:
      case LogAction.ENHANCE_IMAGE:
      case LogAction.ATTACH_NEWS:
        return WorkspaceColors.accentViolet;
      case LogAction.VIEW_RECORD:
      case LogAction.UPLOAD:
      case LogAction.UPDATE:
        return WorkspaceColors.accentEmerald;
      case LogAction.CREATE_CASENOTE:
        return WorkspaceColors.primary;
      case LogAction.DELETE:
      case LogAction.LOGIN_FAIL:
      case LogAction.MODEL_PULL_FAILED:
        return WorkspaceColors.accentRose;
      case LogAction.MODEL_PULL_STARTED:
      case LogAction.MODEL_PULL_COMPLETED:
        return WorkspaceColors.accentAmber;
      case LogAction.LOGIN_OK:
      case LogAction.OTP_SENT:
      case LogAction.OTP_OK:
      case LogAction.PASSWORD_RESET:
        return WorkspaceColors.textSecondary;
    }
  }

  String _shortHash(String hash) => hash.length > 8
      ? '${hash.substring(0, 4)}...${hash.substring(hash.length - 4)}'
      : hash;

  Widget _auditFeed() {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: WorkspaceColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WorkspaceColors.border),
      ),
      child: _recentLogs.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No audit entries yet.',
                  style: TextStyle(color: WorkspaceColors.textMuted)),
            )
          : Column(
              children: [
                for (var i = 0; i < _recentLogs.length; i++)
                  _auditEntry(_recentLogs[i],
                      isFirst: i == 0, isLast: i == _recentLogs.length - 1),
              ],
            ),
    );
  }

  Widget _auditEntry(LogEntry e,
      {required bool isFirst, required bool isLast}) {
    return Container(
      padding: EdgeInsets.only(top: isFirst ? 0 : 12, bottom: 13),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                    color: WorkspaceColors.border.withValues(alpha: 0.6))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('#${e.seq}',
                  style: AppTheme.mono.copyWith(
                      fontSize: 11, color: WorkspaceColors.textMuted)),
              const SizedBox(width: 8),
              _badge(e.action.displayName, _actionColor(e.action)),
              const Spacer(),
              Text(
                _clock.format(DateTime.fromMillisecondsSinceEpoch(e.ts)),
                style: AppTheme.mono
                    .copyWith(fontSize: 11, color: WorkspaceColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${e.action.displayName} for ${e.targetType} [${e.targetId}]',
            style: const TextStyle(
                fontSize: 12, color: WorkspaceColors.textPrimary),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('SHA256:',
                  style: AppTheme.mono.copyWith(
                      fontSize: 11, color: WorkspaceColors.textMuted)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: WorkspaceColors.inputBackground,
                  border: Border.all(color: WorkspaceColors.border),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(_shortHash(e.entryHash),
                    style: AppTheme.mono.copyWith(
                        fontSize: 11, color: WorkspaceColors.textSecondary)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
