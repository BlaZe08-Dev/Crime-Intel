import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../audit/audit_verifier.dart';
import '../../../audit/models/log_entry.dart';
import '../../../main.dart';
import '../../theme/app_theme.dart';

/// The immutable audit trail (`docs/AppFlow.md` §8).
///
/// There is deliberately **no delete or edit control anywhere on this screen**,
/// and no service method behind it that could implement one. "Verify chain"
/// recomputes every hash from scratch, which is the visible proof that nothing
/// has been altered.
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  static final _timestamp = DateFormat('yyyy-MM-dd HH:mm:ss');

  List<LogEntry> _entries = const [];
  AuditVerificationResult? _verification;
  bool _loading = true;
  LogAction? _filter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final services = ServicesScope.of(context);
    setState(() => _loading = true);

    final entries = await services.audit.getAllLogs();
    final verification = await services.verifier.verifyChain();

    if (!mounted) return;
    setState(() {
      _entries = entries.reversed.toList(); // newest first
      _verification = verification;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = _filter == null
        ? _entries
        : _entries.where((e) => e.action == _filter).toList();

    return Column(
      children: [
        _buildHeader(),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (visible.isEmpty)
          const Expanded(
            child: Center(
              child: Text('No entries recorded yet.',
                  style: TextStyle(color: AppColors.textMuted)),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: visible.length,
              itemBuilder: (_, i) => _buildEntry(visible[i]),
            ),
          ),
      ],
    );
  }

  Widget _buildHeader() {
    final verification = _verification;

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
              const SizedBox(width: 14),
              if (verification != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                        verification.isValid
                            ? Icons.verified
                            : Icons.gpp_maybe,
                        size: 15,
                        color: verification.isValid
                            ? AppColors.accentEmerald
                            : AppColors.accentRose,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        verification.isValid
                            ? 'Chain verified · ${verification.totalEntries} entries'
                            : 'TAMPERING DETECTED at #${verification.brokenSeq}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: verification.isValid
                              ? AppColors.accentEmerald
                              : AppColors.accentRose,
                        ),
                      ),
                    ],
                  ),
                ),
              const Spacer(),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.fact_check_outlined, size: 16),
                label: const Text('Verify chain'),
              ),
            ],
          ),
          if (verification != null && !verification.isValid) ...[
            const SizedBox(height: 8),
            Text(verification.errorMessage ?? '',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.accentRose)),
          ],
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

  /// Only offer filters for actions that actually occur, so the bar reflects
  /// the real log rather than the full enum.
  List<LogAction> _presentActions() {
    final present = _entries.map((e) => e.action).toSet().toList();
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

  Widget _buildEntry(LogEntry entry) {
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

  static String _short(String hash) =>
      hash.length <= 16 ? hash : '${hash.substring(0, 16)}…';
}
