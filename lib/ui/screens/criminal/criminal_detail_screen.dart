import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/di/app_services.dart';
import '../../../models/case_note.dart';
import '../../../models/criminal.dart';
import '../../../models/media_item.dart';
import '../../../models/structured_records.dart';
import '../../../models/text_record.dart';
import '../../theme/app_theme.dart';

/// A single criminal's record (`docs/AppFlow.md` §4).
///
/// Opening this screen writes a `VIEW_RECORD` entry to the audit chain, which
/// is what `docs/PRD.md` §3.5 means by "viewing a record is logged". The write
/// happens in `CrimeRepository.openCriminalRecord` rather than here, so the
/// logging cannot be skipped by a caller that forgets.
class CriminalDetailScreen extends StatefulWidget {
  final String criminalId;
  final AppServices services;

  const CriminalDetailScreen({
    super.key,
    required this.criminalId,
    required this.services,
  });

  @override
  State<CriminalDetailScreen> createState() => _CriminalDetailScreenState();
}

class _CriminalDetailScreenState extends State<CriminalDetailScreen> {
  static final _date = DateFormat('yyyy-MM-dd');
  static final _money = NumberFormat.decimalPattern('en_IN');

  Criminal? _criminal;
  List<MediaItem> _media = const [];
  List<TextRecord> _texts = const [];
  List<CdrRecord> _calls = const [];
  List<FinancialTxn> _payments = const [];
  List<CriminalHistory> _history = const [];
  List<CaseNote> _notes = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = widget.services.records;

    // Logged read: this is a human opening a file.
    final criminal = await repo.openCriminalRecord(
      context: widget.services.session,
      criminalId: widget.criminalId,
    );

    final media = await repo.getMediaFor(widget.criminalId);
    final texts = await repo.getTextRecordsFor(widget.criminalId);
    final calls = await repo.getCdrFor(widget.criminalId);
    final payments = await repo.getFinancialFor(widget.criminalId);
    final history = await repo.getHistoryFor(widget.criminalId);
    final notes = await repo.getCaseNotesFor(widget.criminalId);

    if (!mounted) return;
    setState(() {
      _criminal = criminal;
      _media = media;
      _texts = texts;
      _calls = calls;
      _payments = payments;
      _history = history;
      _notes = notes;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final criminal = _criminal;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(criminal?.name ?? widget.criminalId),
        backgroundColor: AppColors.surface,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : criminal == null
              ? const Center(
                  child: Text('Record not found.',
                      style: TextStyle(color: AppColors.textSecondary)),
                )
              : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    _profile(criminal),
                    const SizedBox(height: 22),
                    if (_media.isNotEmpty) ...[
                      _section('Media', Icons.image_outlined),
                      const SizedBox(height: 10),
                      _mediaStrip(),
                      const SizedBox(height: 22),
                    ],
                    if (_texts.isNotEmpty) ...[
                      _section('Reports & Intelligence',
                          Icons.description_outlined),
                      const SizedBox(height: 10),
                      for (final text in _texts) _textRecord(text),
                      const SizedBox(height: 22),
                    ],
                    if (_payments.isNotEmpty) ...[
                      _section('Financial Transactions',
                          Icons.account_balance_outlined),
                      const SizedBox(height: 10),
                      for (final payment in _payments) _payment(payment),
                      const SizedBox(height: 22),
                    ],
                    if (_calls.isNotEmpty) ...[
                      _section('Call Detail Records', Icons.phone_outlined),
                      const SizedBox(height: 10),
                      for (final call in _calls) _call(call),
                      const SizedBox(height: 22),
                    ],
                    if (_history.isNotEmpty) ...[
                      _section('Prior History', Icons.gavel_outlined),
                      const SizedBox(height: 10),
                      for (final item in _history) _historyRow(item),
                      const SizedBox(height: 22),
                    ],
                    _section('Case Notes', Icons.sticky_note_2_outlined),
                    const SizedBox(height: 10),
                    if (_notes.isEmpty)
                      const Text('No case notes yet.',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textMuted))
                    else
                      for (final note in _notes) _note(note),
                  ],
                ),
    );
  }

  Widget _section(String title, IconData icon) => Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
        ],
      );

  Widget _card({required Widget child, Color? borderColor}) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor ?? AppColors.border),
        ),
        child: child,
      );

  Widget _profile(Criminal criminal) => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(criminal.name,
                style: Theme.of(context).textTheme.displayMedium),
            const SizedBox(height: 6),
            Text(
              'Aliases: ${criminal.aliases.join(", ")}  ·  DOB ${criminal.dob}  '
              '·  ${criminal.gender}',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _tag(criminal.status.displayName, AppColors.primary),
                _tag('Risk: ${criminal.riskLevel.displayName}',
                    AppColors.accentAmber),
                _tag(criminal.lastKnownLoc, AppColors.textSecondary),
                if (criminal.isDeleted)
                  _tag('SOFT-DELETED', AppColors.accentRose),
              ],
            ),
            const SizedBox(height: 12),
            Text('Known for: ${criminal.knownFor}',
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textPrimary)),
          ],
        ),
      );

  Widget _tag(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      );

  Widget _mediaStrip() => SizedBox(
        height: 168,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _media.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) {
            final item = _media[i];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    item.filePath,
                    width: 130,
                    height: 130,
                    fit: BoxFit.cover,
                    // Media may be absent until teammates supply real
                    // synthetic images; show why rather than a red X.
                    errorBuilder: (_, __, ___) => Container(
                      width: 130,
                      height: 130,
                      color: AppColors.surfaceElevated,
                      alignment: Alignment.center,
                      child: const Icon(Icons.image_not_supported_outlined,
                          color: AppColors.textMuted),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                SizedBox(
                  width: 130,
                  child: Text(
                    item.type.displayName,
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textMuted),
                  ),
                ),
              ],
            );
          },
        ),
      );

  Widget _textRecord(TextRecord record) => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(record.id,
                    style: AppTheme.mono.copyWith(
                        fontSize: 11, color: AppColors.primary)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(record.title,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ),
                Text(record.kind.displayName,
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textMuted)),
              ],
            ),
            const SizedBox(height: 8),
            Text(record.body,
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.5)),
          ],
        ),
      );

  Widget _payment(FinancialTxn txn) => _card(
        child: Row(
          children: [
            Text(txn.id,
                style: AppTheme.mono
                    .copyWith(fontSize: 11, color: AppColors.primary)),
            const SizedBox(width: 12),
            Expanded(
              child: Text('→ ${txn.counterparty}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ),
            Text('${txn.currency} ${_money.format(txn.amount)}',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const SizedBox(width: 12),
            Text(
              '${txn.channel} · '
              '${_date.format(DateTime.fromMillisecondsSinceEpoch(txn.ts))}',
              style:
                  const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
      );

  Widget _call(CdrRecord call) => _card(
        child: Row(
          children: [
            Text(call.id,
                style: AppTheme.mono
                    .copyWith(fontSize: 11, color: AppColors.primary)),
            const SizedBox(width: 12),
            Expanded(
              child: Text('${call.callerId}  →  ${call.calleeId}',
                  style: AppTheme.mono.copyWith(
                      fontSize: 12, color: AppColors.textSecondary)),
            ),
            Text('${call.durationSec}s',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textPrimary)),
            const SizedBox(width: 12),
            Text(
              '${call.cellSite} · '
              '${_date.format(DateTime.fromMillisecondsSinceEpoch(call.ts))}',
              style:
                  const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
      );

  Widget _historyRow(CriminalHistory item) => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(item.offense,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ),
                Text(item.date,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
            const SizedBox(height: 5),
            Text(item.dispositionNote,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      );

  Widget _note(CaseNote note) {
    final byAssistant = note.author == NoteAuthor.ASSISTANT;
    return _card(
      borderColor: byAssistant
          ? AppColors.accentPurple.withValues(alpha: 0.5)
          : AppColors.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                byAssistant ? Icons.auto_awesome : Icons.person_outline,
                size: 13,
                color: byAssistant
                    ? AppColors.accentPurple
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                note.author.displayName,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: byAssistant
                      ? AppColors.accentPurple
                      : AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                _date.format(
                    DateTime.fromMillisecondsSinceEpoch(note.createdAt)),
                style:
                    const TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(note.text,
              style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textPrimary,
                  height: 1.5)),
        ],
      ),
    );
  }
}
