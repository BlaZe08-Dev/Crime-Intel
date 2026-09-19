import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../audit/audit_verifier.dart';
import '../../../audit/models/log_entry.dart';
import '../../../main.dart';
import '../../../sync/models/sync_models.dart';
import '../../theme/app_theme.dart';

/// The immutable audit trail (`docs/AppFlow.md` §8).
///
/// **Two-Chain Architecture:**
/// - **Local Device Chain:** append-only hash chain maintaining tamper-evidence
///   locally and completely offline (`docs/Schema.md` §8).
/// - **Canonical Central Chain (Neon):** authoritative multi-device chain ordered
///   strictly by server arrival time, recording both local action timestamps and
///   canonical arrival timestamps.
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  static final _timestamp = DateFormat('yyyy-MM-dd HH:mm:ss');

  int _selectedChain = 0; // 0: Local, 1: Central (Neon)

  List<LogEntry> _localEntries = const [];
  AuditVerificationResult? _localVerification;

  List<CanonicalAuditEntry> _canonicalEntries = const [];
  bool? _canonicalValid;

  bool _loading = true;
  String? _centralError;
  LogAction? _filter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final services = ServicesScope.of(context);
    setState(() => _loading = true);

    if (_selectedChain == 0) {
      final entries = await services.audit.getAllLogs();
      final verification = await services.verifier.verifyChain();

      if (!mounted) return;
      setState(() {
        _localEntries = entries.reversed.toList(); // newest first
        _localVerification = verification;
        _loading = false;
      });
    } else {
      if (!services.syncTransport.isConfigured) {
        if (!mounted) return;
        setState(() {
          _canonicalEntries = const [];
          _canonicalValid = null;
          _centralError = 'Central Neon database is not configured in .env.';
          _loading = false;
        });
        return;
      }

      try {
        final logs = await services.syncTransport.fetchCanonicalLogs(limit: 100);
        final valid = await services.syncTransport.verifyCanonicalChain();
        if (!mounted) return;
        setState(() {
          _canonicalEntries = logs;
          _canonicalValid = valid;
          _centralError = null;
          _loading = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _canonicalEntries = const [];
          _canonicalValid = null;
          _centralError = 'Could not fetch central logs: $e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        _buildArchitectureBanner(),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_selectedChain == 1 && _centralError != null)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off,
                        size: 44, color: AppColors.textMuted),
                    const SizedBox(height: 12),
                    Text(
                      _centralError!,
                      style: const TextStyle(color: AppColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Retry Connection'),
                      onPressed: _load,
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Expanded(child: _buildLogList()),
      ],
    );
  }

  Widget _buildArchitectureBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      color: AppColors.surfaceCard,
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _selectedChain == 0
                  ? 'Local Device Chain: Linear tamper-evident log for this terminal. Works 100% offline.'
                  : 'Canonical Central Chain: Multi-investigator authoritative log on Neon, ordered strictly by server arrival time.',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogList() {
    if (_selectedChain == 0) {
      final visible = _filter == null
          ? _localEntries
          : _localEntries.where((e) => e.action == _filter).toList();

      if (visible.isEmpty) {
        return const Center(
          child: Text('No local entries recorded yet.',
              style: TextStyle(color: AppColors.textMuted)),
        );
      }

      return ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: visible.length,
        itemBuilder: (_, i) => _buildLocalEntry(visible[i]),
      );
    } else {
      final visible = _filter == null
          ? _canonicalEntries
          : _canonicalEntries.where((e) => e.action == _filter).toList();

      if (visible.isEmpty) {
        return const Center(
          child: Text('No entries in central Neon log yet.',
              style: TextStyle(color: AppColors.textMuted)),
        );
      }

      return ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: visible.length,
        itemBuilder: (_, i) => _buildCanonicalEntry(visible[i]),
      );
    }
  }

  Widget _buildHeader() {
    final verification = _localVerification;
    final isLocal = _selectedChain == 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Immutable Audit Trail',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(width: 16),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                    value: 0,
                    label: Text('Local Chain'),
                    icon: Icon(Icons.laptop, size: 16),
                  ),
                  ButtonSegment(
                    value: 1,
                    label: Text('Central Neon Chain'),
                    icon: Icon(Icons.cloud_done, size: 16),
                  ),
                ],
                selected: {_selectedChain},
                onSelectionChanged: (set) {
                  setState(() {
                    _selectedChain = set.first;
                    _filter = null;
                  });
                  _load();
                },
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 14),
              if (isLocal && verification != null)
                _buildVerificationBadge(
                  isValid: verification.isValid,
                  text: verification.isValid
                      ? 'Local Chain Verified · ${verification.totalEntries} entries'
                      : 'TAMPERING DETECTED at #${verification.brokenSeq}',
                )
              else if (!isLocal && _canonicalValid != null)
                _buildVerificationBadge(
                  isValid: _canonicalValid!,
                  text: _canonicalValid!
                      ? 'Central Chain Verified (${_canonicalEntries.length} entries)'
                      : 'CENTRAL CHAIN INTEGRITY BROKEN',
                ),
              const Spacer(),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip(null, 'All'),
                for (final action in _presentActions())
                  _filterChip(action, action.displayName),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationBadge({
    required bool isValid,
    required String text,
  }) {
    final color = isValid ? AppColors.accentEmerald : AppColors.accentRose;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isValid ? Icons.verified : Icons.gpp_maybe,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  List<LogAction> _presentActions() {
    final list = _selectedChain == 0
        ? _localEntries.map((e) => e.action)
        : _canonicalEntries.map((e) => e.action);
    final present = list.toSet().toList();
    present.sort((a, b) => a.name.compareTo(b.name));
    return present;
  }

  Widget _filterChip(LogAction? action, String label) {
    final selected = _filter == action;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: selected,
        onSelected: (_) => setState(() => _filter = action),
      ),
    );
  }

  Widget _buildLocalEntry(LogEntry entry) {
    final actorColor = switch (entry.actor) {
      LogActor.INVESTIGATOR => AppColors.primary,
      LogActor.ASSISTANT => AppColors.accentPurple,
      LogActor.SYSTEM => AppColors.textMuted,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('#${entry.seq}',
                  style: AppTheme.mono.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: actorColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(entry.actor.displayName,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: actorColor)),
              ),
              const SizedBox(width: 10),
              Text(entry.action.displayName,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const Spacer(),
              Text(
                _timestamp
                    .format(DateTime.fromMillisecondsSinceEpoch(entry.ts)),
                style: AppTheme.mono
                    .copyWith(fontSize: 11, color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('${entry.targetType} · ${entry.targetId}',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'prev ${_short(entry.prevHash)}  →  this ${_short(entry.entryHash)}',
                  style: AppTheme.mono.copyWith(
                      fontSize: 10, color: AppColors.accentEmerald),
                ),
              ),
              Text('payload ${_short(entry.payloadHash)}',
                  style: AppTheme.mono
                      .copyWith(fontSize: 10, color: AppColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCanonicalEntry(CanonicalAuditEntry entry) {
    final actorColor = switch (entry.actor) {
      LogActor.INVESTIGATOR => AppColors.primary,
      LogActor.ASSISTANT => AppColors.accentPurple,
      LogActor.SYSTEM => AppColors.textMuted,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('CANONICAL #${entry.seq}',
                  style: AppTheme.mono.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accentEmerald)),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text('Device ${entry.deviceId}',
                    style: AppTheme.mono.copyWith(
                        fontSize: 10, color: AppColors.textMuted)),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: actorColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(entry.actor.displayName,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: actorColor)),
              ),
              const SizedBox(width: 10),
              Text(entry.action.displayName,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Arrived: ${_timestamp.format(DateTime.fromMillisecondsSinceEpoch(entry.serverTs))}',
                    style: AppTheme.mono
                        .copyWith(fontSize: 10, color: AppColors.accentEmerald),
                  ),
                  Text(
                    'Local: ${_timestamp.format(DateTime.fromMillisecondsSinceEpoch(entry.localTs))}',
                    style: AppTheme.mono
                        .copyWith(fontSize: 10, color: AppColors.textMuted),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('${entry.targetType} · ${entry.targetId}',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'prev ${_short(entry.prevHash)}  →  this ${_short(entry.entryHash)}',
                  style: AppTheme.mono.copyWith(
                      fontSize: 10, color: AppColors.accentEmerald),
                ),
              ),
              Text('payload ${_short(entry.payloadHash)}',
                  style: AppTheme.mono
                      .copyWith(fontSize: 10, color: AppColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }

  static String _short(String hash) =>
      hash.length <= 16 ? hash : '${hash.substring(0, 16)}…';
}
