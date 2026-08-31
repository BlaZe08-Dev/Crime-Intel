import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../audit/audit_logger.dart';
import '../../../audit/audit_verifier.dart';
import '../../../audit/models/log_entry.dart';
import '../../../core/constants/constants.dart';
import '../../../ingest/ingestion_service.dart';
import '../../../models/criminal.dart';
import '../../theme/app_theme.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final IngestionService _ingestionService = IngestionService.instance;
  final AuditLogger _auditLogger = AuditLogger.instance;
  final AuditVerifier _auditVerifier = AuditVerifier();

  List<Criminal> _criminals = [];
  List<LogEntry> _recentLogs = [];
  AuditVerificationResult? _verificationResult;
  bool _isLoading = true;
  int _entityCount = 0;
  int _edgeCount = 0;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      await _ingestionService.seedDatabaseIfEmpty();
      final criminals = await _ingestionService.getCriminals();
      final entities = await _ingestionService.getAllEntities();
      final edges = await _ingestionService.getAllEdges();
      final recentLogs = await _auditLogger.getRecentLogs(limit: 10);
      final verification = await _auditVerifier.verifyChain();

      setState(() {
        _criminals = criminals;
        _entityCount = entities.length;
        _edgeCount = edges.length;
        _recentLogs = recentLogs;
        _verificationResult = verification;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatCards(),
                  const SizedBox(height: 24),
                  _buildMainContentGrid(),
                ],
              ),
            ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final verification = _verificationResult;
    return AppBar(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.shield_outlined, color: AppColors.primary, size: 20),
                SizedBox(width: 8),
                Text(
                  AppConstants.appName,
                  style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Text(
            'Investigator Workspace',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ],
      ),
      actions: [
        if (verification != null)
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: verification.isValid
                  ? AppColors.accentEmerald.withOpacity(0.15)
                  : AppColors.accentRose.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: verification.isValid
                    ? AppColors.accentEmerald
                    : AppColors.accentRose,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  verification.isValid ? Icons.verified : Icons.warning_amber_rounded,
                  color: verification.isValid
                      ? AppColors.accentEmerald
                      : AppColors.accentRose,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  verification.isValid
                      ? 'Audit Chain Verified (${verification.totalEntries} entries)'
                      : 'Chain Tamper Detected!',
                  style: TextStyle(
                    fontSize: 12,
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
          icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
          tooltip: 'Refresh Dashboard & Verify Log Chain',
          onPressed: _loadDashboardData,
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildStatCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 48) / 4;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _buildStatCard(
              title: 'Active Profiles',
              value: '${_criminals.length}',
              subtitle: 'Synthetic Records Seeded',
              icon: Icons.person_search_outlined,
              color: AppColors.primary,
              width: cardWidth,
            ),
            _buildStatCard(
              title: 'Network Entities',
              value: '$_entityCount',
              subtitle: 'Extracted Nodes',
              icon: Icons.hub_outlined,
              color: AppColors.accentAmber,
              width: cardWidth,
            ),
            _buildStatCard(
              title: 'Relationship Edges',
              value: '$_edgeCount',
              subtitle: 'CDR / Financial / Co-location',
              icon: Icons.share_outlined,
              color: AppColors.accentPurple,
              width: cardWidth,
            ),
            _buildStatCard(
              title: 'Audit Log Entries',
              value: '${_recentLogs.length}',
              subtitle: 'Hash-Chained & Immutable',
              icon: Icons.lock_outline,
              color: AppColors.accentEmerald,
              width: cardWidth,
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required double width,
  }) {
    return Container(
      width: width.clamp(200.0, 400.0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContentGrid() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column: Criminal Network Targets
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('Criminal Network Targets', Icons.groups_outlined),
              const SizedBox(height: 12),
              ..._criminals.map((c) => _buildCriminalCard(c)),
            ],
          ),
        ),
        const SizedBox(width: 24),
        // Right Column: Recent Immutable Audit Trail
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('Immutable Audit Trail (Hash-Chained)', Icons.receipt_long_outlined),
              const SizedBox(height: 12),
              _buildAuditLogFeed(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ],
    );
  }

  Widget _buildCriminalCard(Criminal criminal) {
    final isHub = criminal.id == 'C-001';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHub ? AppColors.accentAmber.withOpacity(0.6) : AppColors.border,
          width: isHub ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.surfaceElevated,
                child: Text(
                  criminal.id,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          criminal.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (isHub) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.accentAmber.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppColors.accentAmber),
                            ),
                            child: const Text(
                              'NETWORK HUB',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.accentAmber,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Aliases: ${criminal.aliases.join(", ")} · Loc: ${criminal.lastKnownLoc}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              _buildRiskBadge(criminal.riskLevel),
              const SizedBox(width: 8),
              _buildStatusChip(criminal.status),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface.withOpacity(0.6),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Known For: ${criminal.knownFor}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskBadge(RiskLevel risk) {
    Color color;
    switch (risk) {
      case RiskLevel.HIGH:
        color = AppColors.accentRose;
        break;
      case RiskLevel.MED:
        color = AppColors.accentAmber;
        break;
      case RiskLevel.LOW:
        color = AppColors.accentEmerald;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color),
      ),
      child: Text(
        risk.displayName,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _buildStatusChip(CriminalStatus status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        status.displayName,
        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
    );
  }

  Widget _buildAuditLogFeed() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          if (_recentLogs.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20.0),
              child: Text('No audit logs recorded yet.', style: TextStyle(color: AppColors.textMuted)),
            )
          else
            ..._recentLogs.map((entry) {
              final dateStr = DateFormat('HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(entry.ts));
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border.withOpacity(0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '#${entry.seq}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          entry.action.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textPrimary),
                        ),
                        const Spacer(),
                        Text(
                          dateStr,
                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Actor: ${entry.actor.displayName} · Target: ${entry.targetType} [${entry.targetId}]',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Hash: ${entry.entryHash.substring(0, 16)}...',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        color: AppColors.accentEmerald,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
