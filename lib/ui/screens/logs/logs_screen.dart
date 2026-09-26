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
        final logs =
            await services.syncTransport.fetchCanonicalLogs(limit: 100);
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
                        size: 44, color: WorkspaceColors.textMuted),
                    const SizedBox(height: 12),
                    Text(
                      _centralError!,
                      style:
                          const TextStyle(color: WorkspaceColors.textSecondary),
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
      color: WorkspaceColors.surfaceCard,
      child: Row(
        children: [
          const Icon(Icons.info_outline,
              size: 14, color: WorkspaceColors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _selectedChain == 0
                  ? 'Local Device Chain: Linear tamper-evident log for this terminal. Works 100% offline.'
                  : 'Canonical Central Chain: Multi-investigator authoritative log on Neon, ordered strictly by server arrival time.',
              style: const TextStyle(
                  fontSize: 11, color: WorkspaceColors.textMuted),
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
              style: TextStyle(color: WorkspaceColors.textMuted)),
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
              style: TextStyle(color: WorkspaceColors.textMuted)),
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

    final isValid = isLocal ? verification?.isValid : _canonicalValid;
    final entryCount =
        isLocal ? _localEntries.length : _canonicalEntries.length;
    final rootHash = isLocal
        ? (_localEntries.isNotEmpty ? _localEntries.first.entryHash : null)
        : (_canonicalEntries.isNotEmpty
            ? _canonicalEntries.first.entryHash
            : null);

    return Container(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: WorkspaceColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Immutable Audit Trail',
                  style: TextStyle(
                      fontFamily: AppTheme.displayFamily,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: WorkspaceColors.textPrimary)),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: WorkspaceColors.inputBackground,
                  border: Border.all(color: WorkspaceColors.border),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('LEDGER:${isLocal ? "LOCAL" : "CENTRAL"}',
                    style: AppTheme.mono.copyWith(
                        fontSize: 11, color: WorkspaceColors.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
              'Every action is recorded in a tamper-evident, hash-chained log for evidentiary integrity.',
              style: TextStyle(
                  fontSize: 13, color: WorkspaceColors.textSecondary)),
          const SizedBox(height: 16),
          if (isValid != null)
            _buildVerificationBanner(isValid, entryCount, rootHash),
          const SizedBox(height: 16),
          Row(
            children: [
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

  Widget _buildVerificationBanner(
      bool isValid, int entryCount, String? rootHash) {
    final color =
        isValid ? WorkspaceColors.accentEmerald : WorkspaceColors.accentRose;
    final verification = _localVerification;
    final isLocal = _selectedChain == 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isValid ? Icons.check_circle_outline : Icons.gpp_maybe,
              color: color, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isValid
                          ? 'Chain verified · $entryCount entries'
                          : 'Tampering detected',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: WorkspaceColors.textPrimary),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(isValid ? 'ZERO DRIFT' : 'DRIFT DETECTED',
                          style: AppTheme.mono
                              .copyWith(fontSize: 10, color: color)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (rootHash != null)
                      Text('Root: ${_short(rootHash)}',
                          style: AppTheme.mono.copyWith(
                              fontSize: 11, color: WorkspaceColors.textMuted)),
                    if (isLocal && verification != null)
                      Text(
                          'Last validation: ${_timestamp.format(DateTime.fromMillisecondsSinceEpoch(verification.checkedAt))}',
                          style: AppTheme.mono.copyWith(
                              fontSize: 11, color: WorkspaceColors.textMuted)),
                    Text(
                        isValid
                            ? '0 discrepancies detected'
                            : 'break at #${verification?.brokenSeq ?? "?"}',
                        style: AppTheme.mono.copyWith(
                            fontSize: 11, color: WorkspaceColors.textMuted)),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              border: Border.all(color: color.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(isValid ? 'INTEGRITY 100%' : 'INTEGRITY COMPROMISED',
                style: AppTheme.mono.copyWith(
                    fontSize: 11, fontWeight: FontWeight.bold, color: color)),
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
      LogActor.INVESTIGATOR => WorkspaceColors.primary,
      LogActor.ASSISTANT => WorkspaceColors.accentViolet,
      LogActor.SYSTEM => WorkspaceColors.textMuted,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WorkspaceColors.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: WorkspaceColors.border),
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
                      color: WorkspaceColors.primary)),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                      color: WorkspaceColors.textPrimary)),
              const Spacer(),
              Text(
                _timestamp
                    .format(DateTime.fromMillisecondsSinceEpoch(entry.ts)),
                style: AppTheme.mono
                    .copyWith(fontSize: 11, color: WorkspaceColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('${entry.targetType} · ${entry.targetId}',
              style: const TextStyle(
                  fontSize: 12, color: WorkspaceColors.textSecondary)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'prev ${_short(entry.prevHash)}  →  this ${_short(entry.entryHash)}',
                  style: AppTheme.mono.copyWith(
                      fontSize: 10, color: WorkspaceColors.accentEmerald),
                ),
              ),
              Text('payload ${_short(entry.payloadHash)}',
                  style: AppTheme.mono.copyWith(
                      fontSize: 10, color: WorkspaceColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCanonicalEntry(CanonicalAuditEntry entry) {
    final actorColor = switch (entry.actor) {
      LogActor.INVESTIGATOR => WorkspaceColors.primary,
      LogActor.ASSISTANT => WorkspaceColors.accentViolet,
      LogActor.SYSTEM => WorkspaceColors.textMuted,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WorkspaceColors.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: WorkspaceColors.border),
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
                      color: WorkspaceColors.accentEmerald)),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: WorkspaceColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: WorkspaceColors.border),
                ),
                child: Text('Device ${entry.deviceId}',
                    style: AppTheme.mono.copyWith(
                        fontSize: 10, color: WorkspaceColors.textMuted)),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                      color: WorkspaceColors.textPrimary)),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Arrived: ${_timestamp.format(DateTime.fromMillisecondsSinceEpoch(entry.serverTs))}',
                    style: AppTheme.mono.copyWith(
                        fontSize: 10, color: WorkspaceColors.accentEmerald),
                  ),
                  Text(
                    'Local: ${_timestamp.format(DateTime.fromMillisecondsSinceEpoch(entry.localTs))}',
                    style: AppTheme.mono.copyWith(
                        fontSize: 10, color: WorkspaceColors.textMuted),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('${entry.targetType} · ${entry.targetId}',
              style: const TextStyle(
                  fontSize: 12, color: WorkspaceColors.textSecondary)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'prev ${_short(entry.prevHash)}  →  this ${_short(entry.entryHash)}',
                  style: AppTheme.mono.copyWith(
                      fontSize: 10, color: WorkspaceColors.accentEmerald),
                ),
              ),
              Text('payload ${_short(entry.payloadHash)}',
                  style: AppTheme.mono.copyWith(
                      fontSize: 10, color: WorkspaceColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }

  static String _short(String hash) =>
      hash.length <= 16 ? hash : '${hash.substring(0, 16)}…';
}
