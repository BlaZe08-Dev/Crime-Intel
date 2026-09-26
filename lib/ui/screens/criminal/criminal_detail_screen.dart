import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/di/app_services.dart';
import '../../../models/case_note.dart';
import '../../../models/criminal.dart';
import '../../../models/media_item.dart';
import '../../../models/structured_records.dart';
import '../../../models/text_record.dart';
import '../../../core/utils/id_generator.dart';
import '../../theme/app_theme.dart';
import '../../widgets/sync_status_badge.dart';
import '../../../main.dart';

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
  static final _timestamp = DateFormat('yyyy-MM-dd HH:mm:ss');
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
    try {
      final repo = widget.services.records;

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
    } catch (e, st) {
      debugPrint('ERROR in CriminalDetailScreen._load: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _uploadMedia() async {
    const imageTypes = XTypeGroup(
      label: 'Images',
      extensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    const docTypes = XTypeGroup(
      label: 'Documents',
      extensions: ['pdf', 'txt', 'doc', 'docx', 'md', 'json', 'csv'],
    );
    final file = await openFile(acceptedTypeGroups: [imageTypes, docTypes]);
    if (file == null || !mounted) return;

    final ext = file.name.split('.').last.toLowerCase();
    final isDoc =
        ['pdf', 'txt', 'doc', 'docx', 'md', 'json', 'csv'].contains(ext);
    final mediaType = isDoc ? MediaType.DOCUMENT : MediaType.PHOTO;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Add ${isDoc ? 'document' : 'media'} to this record?'),
        content: Text(
          'The selected file will be registered against ${widget.criminalId} '
          'and logged in the immutable audit trail. Saved to local storage immediately '
          'and queued for central synchronization.\n\n${file.name}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm upload'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await widget.services.records.addMedia(
        context: widget.services.session,
        item: MediaItem(
          id: IdGenerator.generate('MEDIA'),
          criminalId: widget.criminalId,
          type: mediaType,
          filePath: file.path,
          caption: 'Investigator upload: ${file.name}',
          isSynthetic: true,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          uploadedByInvestigatorId: widget.services.session.investigatorId,
        ),
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '${mediaType.displayName} uploaded and added to the audit log.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not upload media: $error')),
      );
    }
  }

  Future<void> _deleteMedia(MediaItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: WorkspaceColors.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: WorkspaceColors.border),
        ),
        title: const Row(
          children: [
            Icon(Icons.delete_outline,
                color: WorkspaceColors.accentRose, size: 22),
            SizedBox(width: 8),
            Text('Confirm Deletion',
                style: TextStyle(color: WorkspaceColors.textPrimary)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${item.caption.isEmpty ? item.type.displayName : item.caption}"?\n\n'
          'This will soft-delete the item and record the action in the audit trail.',
          style: const TextStyle(
              color: WorkspaceColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: WorkspaceColors.accentRose,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await widget.services.records.deleteMedia(
        context: widget.services.session,
        mediaId: item.id,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '${item.type.displayName} soft-deleted and logged to audit trail.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete media: $error')),
      );
    }
  }

  Future<void> _addCaseNote() async {
    final textController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: WorkspaceColors.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: WorkspaceColors.border),
        ),
        title: const Row(
          children: [
            Icon(Icons.note_add_outlined,
                color: WorkspaceColors.primary, size: 22),
            SizedBox(width: 10),
            Text('Add Case Note / Detail',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Record new investigative intelligence or observations regarding ${_criminal?.name ?? widget.criminalId}. '
                  'Saves to local SQLite immediately (fully offline) and logs in the local audit chain.',
                  style: const TextStyle(
                      fontSize: 12, color: WorkspaceColors.textSecondary),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: textController,
                  maxLines: 5,
                  autofocus: true,
                  style: const TextStyle(
                      fontSize: 13, color: WorkspaceColors.textPrimary),
                  decoration: const InputDecoration(
                    hintText:
                        'Enter case details, observations, notes, or tips...',
                    hintStyle: TextStyle(
                        fontSize: 12, color: WorkspaceColors.textMuted),
                    filled: true,
                    fillColor: WorkspaceColors.surfaceCard,
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Note content cannot be empty.';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: WorkspaceColors.primary,
              foregroundColor: Colors.black,
            ),
            icon: const Icon(Icons.save_outlined, size: 16),
            label: const Text('Save Note'),
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialogCtx, true);
              }
            },
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final text = textController.text.trim();
    if (text.isEmpty) return;

    try {
      await widget.services.records.writeCaseNote(
        context: widget.services.session,
        criminalId: widget.criminalId,
        text: text,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Case note saved and logged to the audit chain.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save case note: $error')),
      );
    }
  }

  Future<void> _addCdrRecord() async {
    final callerController = TextEditingController();
    final calleeController = TextEditingController();
    final durationController = TextEditingController(text: '60');
    final cellSiteController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: WorkspaceColors.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: WorkspaceColors.border),
        ),
        title: const Row(
          children: [
            Icon(Icons.add_call, color: WorkspaceColors.primary, size: 22),
            SizedBox(width: 10),
            Text('Add Call Detail Record (CDR)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Record a call detail record for ${_criminal?.name ?? widget.criminalId}. '
                    'Saves to local SQLite immediately and logs to the immutable audit chain.',
                    style: const TextStyle(
                        fontSize: 12, color: WorkspaceColors.textSecondary),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: callerController,
                    style: const TextStyle(
                        fontSize: 13, color: WorkspaceColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Caller Number / ID *',
                      hintText: '+91-98100-99001',
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) => val == null || val.trim().isEmpty
                        ? 'Caller ID cannot be empty.'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: calleeController,
                    style: const TextStyle(
                        fontSize: 13, color: WorkspaceColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Callee Number / ID *',
                      hintText: '+91-98200-11223',
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) => val == null || val.trim().isEmpty
                        ? 'Callee ID cannot be empty.'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: durationController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                        fontSize: 13, color: WorkspaceColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Duration (seconds) *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) =>
                        val == null || int.tryParse(val.trim()) == null
                            ? 'Enter valid duration in seconds.'
                            : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: cellSiteController,
                    style: const TextStyle(
                        fontSize: 13, color: WorkspaceColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Cell Site / Tower *',
                      hintText: 'Pune-Sector-4',
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) => val == null || val.trim().isEmpty
                        ? 'Cell site cannot be empty.'
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: WorkspaceColors.primary,
              foregroundColor: Colors.black,
            ),
            icon: const Icon(Icons.save_outlined, size: 16),
            label: const Text('Save Record'),
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialogCtx, true);
              }
            },
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final record = CdrRecord(
        id: IdGenerator.generate('CDR'),
        criminalId: widget.criminalId,
        callerId: callerController.text.trim(),
        calleeId: calleeController.text.trim(),
        durationSec: int.parse(durationController.text.trim()),
        cellSite: cellSiteController.text.trim(),
        ts: DateTime.now().millisecondsSinceEpoch,
      );
      await widget.services.records.addCdrRecord(
        context: widget.services.session,
        record: record,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Call detail record added and logged to the audit chain.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save call record: $error')),
      );
    }
  }

  Future<void> _addFinancialTxn() async {
    final counterpartyController = TextEditingController();
    final amountController = TextEditingController();
    final channelController = TextEditingController(text: 'NEFT');
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: WorkspaceColors.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: WorkspaceColors.border),
        ),
        title: const Row(
          children: [
            Icon(Icons.add_card, color: WorkspaceColors.primary, size: 22),
            SizedBox(width: 10),
            Text('Add Financial Transaction',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Record a financial transaction involving ${_criminal?.name ?? widget.criminalId}. '
                    'Saves to local SQLite immediately and logs to the immutable audit chain.',
                    style: const TextStyle(
                        fontSize: 12, color: WorkspaceColors.textSecondary),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: counterpartyController,
                    style: const TextStyle(
                        fontSize: 13, color: WorkspaceColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Counterparty / Beneficiary *',
                      hintText: 'Zenith Impex',
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) => val == null || val.trim().isEmpty
                        ? 'Counterparty cannot be empty.'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: amountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(
                        fontSize: 13, color: WorkspaceColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Amount (INR) *',
                      hintText: '500000',
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) =>
                        val == null || double.tryParse(val.trim()) == null
                            ? 'Enter valid numeric amount.'
                            : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: channelController,
                    style: const TextStyle(
                        fontSize: 13, color: WorkspaceColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Channel / Method *',
                      hintText: 'Hawala, Cash, Wire, UPI',
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) => val == null || val.trim().isEmpty
                        ? 'Channel cannot be empty.'
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: WorkspaceColors.primary,
              foregroundColor: Colors.black,
            ),
            icon: const Icon(Icons.save_outlined, size: 16),
            label: const Text('Save Transaction'),
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialogCtx, true);
              }
            },
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final txn = FinancialTxn(
        id: IdGenerator.generate('TXN'),
        criminalId: widget.criminalId,
        counterparty: counterpartyController.text.trim(),
        amount: double.parse(amountController.text.trim()),
        currency: 'INR',
        channel: channelController.text.trim(),
        ts: DateTime.now().millisecondsSinceEpoch,
      );
      await widget.services.records.addFinancialTxn(
        context: widget.services.session,
        txn: txn,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Financial transaction added and logged to the audit chain.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save transaction: $error')),
      );
    }
  }

  Future<void> _addCriminalHistory() async {
    final offenseController = TextEditingController();
    final dateController = TextEditingController(
      text: DateFormat('yyyy-MM-dd').format(DateTime.now()),
    );
    final dispositionController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: WorkspaceColors.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: WorkspaceColors.border),
        ),
        title: const Row(
          children: [
            Icon(Icons.history_edu_outlined,
                color: WorkspaceColors.primary, size: 22),
            SizedBox(width: 10),
            Text('Add Prior Criminal History',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Record prior criminal history / offense for ${_criminal?.name ?? widget.criminalId}. '
                    'Saves to local SQLite immediately and logs to the immutable audit chain.',
                    style: const TextStyle(
                        fontSize: 12, color: WorkspaceColors.textSecondary),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: offenseController,
                    style: const TextStyle(
                        fontSize: 13, color: WorkspaceColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Offense / Charge *',
                      hintText: 'IPC 420 / Phishing Fraud',
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) => val == null || val.trim().isEmpty
                        ? 'Offense cannot be empty.'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: dateController,
                    style: const TextStyle(
                        fontSize: 13, color: WorkspaceColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Date (YYYY-MM-DD) *',
                      hintText: '2023-08-15',
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) => val == null || val.trim().isEmpty
                        ? 'Date cannot be empty.'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: dispositionController,
                    maxLines: 2,
                    style: const TextStyle(
                        fontSize: 13, color: WorkspaceColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Disposition / Case Status *',
                      hintText: 'Chargesheet filed, trial ongoing',
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) => val == null || val.trim().isEmpty
                        ? 'Disposition cannot be empty.'
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: WorkspaceColors.primary,
              foregroundColor: Colors.black,
            ),
            icon: const Icon(Icons.save_outlined, size: 16),
            label: const Text('Save History'),
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialogCtx, true);
              }
            },
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final history = CriminalHistory(
        id: IdGenerator.generate('HIST'),
        criminalId: widget.criminalId,
        offense: offenseController.text.trim(),
        date: dateController.text.trim(),
        dispositionNote: dispositionController.text.trim(),
      );
      await widget.services.records.addCriminalHistory(
        context: widget.services.session,
        history: history,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Criminal history record added and logged to the audit chain.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save criminal history: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final criminal = _criminal;

    return ServicesScope(
      services: widget.services,
      child: Scaffold(
        backgroundColor: WorkspaceColors.background,
        body: Column(
          children: [
            _topBar(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : criminal == null
                      ? const Center(
                          child: Text('Record not found.',
                              style: TextStyle(
                                  color: WorkspaceColors.textSecondary)),
                        )
                      : _content(criminal),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(Criminal criminal) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _profile(criminal),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 7,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_texts.isNotEmpty) ...[
                      _section(
                          'Reports & Intelligence', Icons.description_outlined),
                      const SizedBox(height: 10),
                      for (final text in _texts) _textRecord(text),
                      const SizedBox(height: 22),
                    ],
                    _financialHeader(),
                    const SizedBox(height: 10),
                    if (_payments.isEmpty)
                      const Text('No financial transactions recorded.',
                          style: TextStyle(
                              fontSize: 12, color: WorkspaceColors.textMuted))
                    else ...[
                      _tableHeader(const [
                        ('DATE', 3),
                        ('COUNTERPARTY', 4),
                        ('AMOUNT', 3),
                        ('CHANNEL', 3),
                      ]),
                      for (final payment in _payments) _payment(payment),
                    ],
                    const SizedBox(height: 22),
                    _cdrHeader(),
                    const SizedBox(height: 10),
                    if (_calls.isEmpty)
                      const Text('No call detail records recorded.',
                          style: TextStyle(
                              fontSize: 12, color: WorkspaceColors.textMuted))
                    else ...[
                      _tableHeader(const [
                        ('TIMESTAMP', 4),
                        ('IDENTIFIER', 4),
                        ('DURATION', 2),
                        ('TOWER / CELL ID', 3),
                      ]),
                      for (final call in _calls) _call(call),
                    ],
                    const SizedBox(height: 22),
                    _historyHeader(),
                    const SizedBox(height: 10),
                    if (_history.isEmpty)
                      const Text('No prior criminal history recorded.',
                          style: TextStyle(
                              fontSize: 12, color: WorkspaceColors.textMuted))
                    else
                      for (final item in _history) _historyRow(item),
                    const SizedBox(height: 22),
                    _caseNotesHeader(),
                    const SizedBox(height: 10),
                    if (_notes.isEmpty)
                      _emptyCaseNotes()
                    else
                      for (final note in _notes) _note(note),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _mediaHeader(),
                    const SizedBox(height: 10),
                    if (_media.isEmpty)
                      const Text('No media or documents uploaded.',
                          style: TextStyle(
                              fontSize: 12, color: WorkspaceColors.textMuted))
                    else
                      _mediaStrip(),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _topBar() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        decoration: const BoxDecoration(
          color: WorkspaceColors.surfaceCard,
          border: Border(bottom: BorderSide(color: WorkspaceColors.border)),
        ),
        child: Row(
          children: [
            TextButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Back to Targets'),
              style: TextButton.styleFrom(
                  foregroundColor: WorkspaceColors.textSecondary),
            ),
            const Spacer(),
            const SyncStatusBadge(compact: true),
            const SizedBox(width: 16),
            OutlinedButton.icon(
              onPressed: _addCaseNote,
              icon: const Icon(Icons.note_add_outlined, size: 16),
              label: const Text('Add Case Note'),
              style: OutlinedButton.styleFrom(
                foregroundColor: WorkspaceColors.textPrimary,
                side: const BorderSide(color: WorkspaceColors.border),
              ),
            ),
          ],
        ),
      );

  Widget _tableHeader(List<(String, int)> columns) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          children: [
            for (final (label, flex) in columns)
              Expanded(
                flex: flex,
                child: Text(label,
                    style: AppTheme.mono.copyWith(
                        fontSize: 10,
                        letterSpacing: 0.5,
                        color: WorkspaceColors.textMuted)),
              ),
          ],
        ),
      );

  Widget _emptyCaseNotes() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32),
        decoration: BoxDecoration(
          border: Border.all(color: WorkspaceColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            const Icon(Icons.sticky_note_2_outlined,
                size: 28, color: WorkspaceColors.textMuted),
            const SizedBox(height: 10),
            const Text('No case notes yet.',
                style: TextStyle(
                    fontSize: 13, color: WorkspaceColors.textSecondary)),
            const SizedBox(height: 4),
            const Text(
              'Record observations or tag evidentiary hypotheses to assist\nteam investigators.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: WorkspaceColors.textMuted),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _addCaseNote,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add First Note'),
              style: OutlinedButton.styleFrom(
                foregroundColor: WorkspaceColors.textPrimary,
                side: const BorderSide(color: WorkspaceColors.border),
              ),
            ),
          ],
        ),
      );

  Widget _section(String title, IconData icon) => Row(
        children: [
          Icon(icon, size: 18, color: WorkspaceColors.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(title,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge),
          ),
        ],
      );

  Widget _mediaHeader() => Row(
        children: [
          Expanded(
              child: _section('Media & Documents', Icons.perm_media_outlined)),
          OutlinedButton.icon(
            onPressed: _uploadMedia,
            icon: const Icon(Icons.upload_file_outlined, size: 17),
            label: const Text('Upload file/media'),
          ),
        ],
      );

  Widget _financialHeader() => Row(
        children: [
          Expanded(
              child: _section(
                  'Financial Transactions', Icons.account_balance_outlined)),
          OutlinedButton.icon(
            onPressed: _addFinancialTxn,
            icon: const Icon(Icons.add_card, size: 17),
            label: const Text('Add transaction'),
          ),
        ],
      );

  Widget _cdrHeader() => Row(
        children: [
          Expanded(
              child: _section('Call Detail Records', Icons.phone_outlined)),
          OutlinedButton.icon(
            onPressed: _addCdrRecord,
            icon: const Icon(Icons.add_call, size: 17),
            label: const Text('Add call record'),
          ),
        ],
      );

  Widget _historyHeader() => Row(
        children: [
          Expanded(child: _section('Prior History', Icons.gavel_outlined)),
          OutlinedButton.icon(
            onPressed: _addCriminalHistory,
            icon: const Icon(Icons.history_edu_outlined, size: 17),
            label: const Text('Add history record'),
          ),
        ],
      );

  Widget _caseNotesHeader() => Row(
        children: [
          Expanded(
              child: _section(
                  'Case Notes & Details', Icons.sticky_note_2_outlined)),
          OutlinedButton.icon(
            onPressed: _addCaseNote,
            icon: const Icon(Icons.add_comment_outlined, size: 17),
            label: const Text('Add case note'),
          ),
        ],
      );

  Widget _card({required Widget child, Color? borderColor}) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: WorkspaceColors.surfaceCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor ?? WorkspaceColors.border),
        ),
        child: child,
      );

  Widget _profile(Criminal criminal) {
    final riskColor = switch (criminal.riskLevel) {
      RiskLevel.HIGH => WorkspaceColors.accentRose,
      RiskLevel.MED => WorkspaceColors.accentAmber,
      RiskLevel.LOW => WorkspaceColors.accentEmerald,
    };
    final statusColor = switch (criminal.status) {
      CriminalStatus.AT_LARGE => WorkspaceColors.accentRose,
      CriminalStatus.IN_CUSTODY => WorkspaceColors.accentEmerald,
      CriminalStatus.UNDER_WATCH => WorkspaceColors.textSecondary,
      CriminalStatus.DECEASED => WorkspaceColors.textMuted,
    };

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 6,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: WorkspaceColors.inputBackground,
                  border: Border.all(color: WorkspaceColors.border),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(criminal.id,
                    style: AppTheme.mono.copyWith(
                        fontSize: 11, color: WorkspaceColors.textSecondary)),
              ),
              Text(criminal.name,
                  style: const TextStyle(
                      fontFamily: AppTheme.displayFamily,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: WorkspaceColors.textPrimary)),
              _tag(criminal.riskLevel.displayName, riskColor),
              _tag(criminal.status.displayName, statusColor),
              if (criminal.isDeleted)
                _tag('SOFT-DELETED', WorkspaceColors.accentRose),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Aliases: ${criminal.aliases.join(", ")}  ·  DOB ${criminal.dob}  '
            '·  ${criminal.gender}  ·  ${criminal.lastKnownLoc}',
            style: const TextStyle(
                fontSize: 12, color: WorkspaceColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Text('Known for: ${criminal.knownFor}',
              style: const TextStyle(
                  fontSize: 13, color: WorkspaceColors.textPrimary)),
        ],
      ),
    );
  }

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
            final isDoc = item.type == MediaType.DOCUMENT;
            final isUploader = item.uploadedByInvestigatorId ==
                widget.services.session.investigatorId;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: isDoc
                          ? Container(
                              width: 130,
                              height: 130,
                              color: WorkspaceColors.surfaceElevated,
                              alignment: Alignment.center,
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.description_outlined,
                                      size: 40, color: WorkspaceColors.primary),
                                  const SizedBox(height: 8),
                                  Text(
                                    item.caption.replaceFirst(
                                        'Investigator upload: ', ''),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: WorkspaceColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : (item.filePath.startsWith('assets/')
                              ? Image.asset(
                                  item.filePath,
                                  width: 130,
                                  height: 130,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _missingMedia(),
                                )
                              : Image.file(
                                  File(item.filePath),
                                  width: 130,
                                  height: 130,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _missingMedia(),
                                )),
                    ),
                    if (isUploader)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Material(
                          color: Colors.black.withValues(alpha: 0.65),
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: Tooltip(
                            message: 'Delete media',
                            child: InkWell(
                              key: Key('delete-media-${item.id}'),
                              onTap: () => _deleteMedia(item),
                              hoverColor: WorkspaceColors.accentRose
                                  .withValues(alpha: 0.2),
                              child: const Padding(
                                padding: EdgeInsets.all(5),
                                child: Icon(
                                  Icons.delete_outline,
                                  size: 16,
                                  color: WorkspaceColors.accentRose,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                SizedBox(
                  width: 130,
                  child: Text(
                    item.type.displayName,
                    style: const TextStyle(
                        fontSize: 10, color: WorkspaceColors.textMuted),
                  ),
                ),
              ],
            );
          },
        ),
      );

  Widget _missingMedia() => Container(
        width: 130,
        height: 130,
        color: WorkspaceColors.surfaceElevated,
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported_outlined,
            color: WorkspaceColors.textMuted),
      );

  Widget _textRecord(TextRecord record) => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(record.id,
                    style: AppTheme.mono.copyWith(
                        fontSize: 11, color: WorkspaceColors.primary)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(record.title,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: WorkspaceColors.textPrimary)),
                ),
                Text(record.kind.displayName,
                    style: const TextStyle(
                        fontSize: 10, color: WorkspaceColors.textMuted)),
              ],
            ),
            const SizedBox(height: 8),
            Text(record.body,
                style: const TextStyle(
                    fontSize: 12,
                    color: WorkspaceColors.textSecondary,
                    height: 1.5)),
          ],
        ),
      );

  Widget _payment(FinancialTxn txn) => _card(
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                  _date.format(DateTime.fromMillisecondsSinceEpoch(txn.ts)),
                  style: AppTheme.mono.copyWith(
                      fontSize: 11, color: WorkspaceColors.textMuted)),
            ),
            Expanded(
              flex: 4,
              child: Text(txn.counterparty,
                  style: const TextStyle(
                      fontSize: 12, color: WorkspaceColors.textPrimary)),
            ),
            Expanded(
              flex: 3,
              child: Text('${txn.currency} ${_money.format(txn.amount)}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: WorkspaceColors.textPrimary)),
            ),
            Expanded(
              flex: 3,
              child: Text(txn.channel,
                  style: const TextStyle(
                      fontSize: 12, color: WorkspaceColors.textSecondary)),
            ),
          ],
        ),
      );

  Widget _call(CdrRecord call) => _card(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: Text(
                  _timestamp
                      .format(DateTime.fromMillisecondsSinceEpoch(call.ts)),
                  style: AppTheme.mono.copyWith(
                      fontSize: 11, color: WorkspaceColors.textMuted)),
            ),
            Expanded(
              flex: 4,
              child: Text('${call.callerId} → ${call.calleeId}',
                  style: AppTheme.mono.copyWith(
                      fontSize: 11, color: WorkspaceColors.textPrimary)),
            ),
            Expanded(
              flex: 2,
              child: Text('${call.durationSec}s',
                  style: const TextStyle(
                      fontSize: 12, color: WorkspaceColors.textPrimary)),
            ),
            Expanded(
              flex: 3,
              child: Text(call.cellSite,
                  style: const TextStyle(
                      fontSize: 11, color: WorkspaceColors.textMuted)),
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
                          color: WorkspaceColors.textPrimary)),
                ),
                Text(item.date,
                    style: const TextStyle(
                        fontSize: 11, color: WorkspaceColors.textMuted)),
              ],
            ),
            const SizedBox(height: 5),
            Text(item.dispositionNote,
                style: const TextStyle(
                    fontSize: 12, color: WorkspaceColors.textSecondary)),
          ],
        ),
      );

  Widget _note(CaseNote note) {
    final byAssistant = note.author == NoteAuthor.ASSISTANT;
    return _card(
      borderColor: byAssistant
          ? WorkspaceColors.accentViolet.withValues(alpha: 0.5)
          : WorkspaceColors.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                byAssistant ? Icons.auto_awesome : Icons.person_outline,
                size: 13,
                color: byAssistant
                    ? WorkspaceColors.accentViolet
                    : WorkspaceColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                note.author.displayName,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: byAssistant
                      ? WorkspaceColors.accentViolet
                      : WorkspaceColors.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                _date.format(
                    DateTime.fromMillisecondsSinceEpoch(note.createdAt)),
                style: const TextStyle(
                    fontSize: 11, color: WorkspaceColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(note.text,
              style: const TextStyle(
                  fontSize: 12,
                  color: WorkspaceColors.textPrimary,
                  height: 1.5)),
        ],
      ),
    );
  }
}
