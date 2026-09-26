import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/constants/constants.dart';
import '../../../core/errors/app_exceptions.dart';
import '../../../llm/llm_client.dart';
import '../../../main.dart';
import '../../../rag/rag_service.dart';
import '../../theme/app_theme.dart';

/// One rendered turn in the transcript.
class _Turn {
  final bool fromUser;
  final String text;
  final List<RetrievedSource> sources;
  final bool grounded;
  final bool isError;
  final Duration? latency;
  final String? noteId;

  const _Turn({
    required this.fromUser,
    required this.text,
    this.sources = const [],
    this.grounded = true,
    this.isError = false,
    this.latency,
    this.noteId,
  });
}

/// Chat-over-database (`docs/AppFlow.md` §3).
///
/// Answers are rendered with the record ids they were built from, so every
/// claim is traceable. When retrieval finds nothing the refusal is shown as
/// such rather than dressed up as an answer.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Turn> _turns = [];

  bool _busy = false;
  bool _indexReady = false;
  bool _checking = true;
  String? _indexNotice;
  LlmHealth? _health;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkReadiness());
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Reports what is and is not ready, rather than failing at first question.
  Future<void> _checkReadiness() async {
    final services = ServicesScope.of(context);
    setState(() => _checking = true);

    final health = await services.llm.checkHealth();
    final chunks = await services.vectors.count();

    if (!mounted) return;
    setState(() {
      _health = health;
      _indexReady = chunks > 0;
      _checking = false;
      _indexNotice = chunks > 0 ? '$chunks records indexed' : null;
    });
  }

  Future<void> _buildIndex() async {
    final services = ServicesScope.of(context);
    setState(() {
      _busy = true;
      _indexNotice = 'Embedding records with ${AppConfig.embedModel}...';
    });

    try {
      final result = await services.indexer.rebuild(context: services.session);
      if (!mounted) return;
      setState(() {
        _indexReady = result.chunkCount > 0;
        _indexNotice = '${result.chunkCount} records indexed '
            '(${result.dimensions}-dim) in '
            '${(result.duration.inMilliseconds / 1000).toStringAsFixed(1)}s';
      });
    } on AppException catch (error) {
      if (!mounted) return;
      setState(() => _indexNotice = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final question = _input.text.trim();
    if (question.isEmpty || _busy) return;

    final services = ServicesScope.of(context);
    _input.clear();

    setState(() {
      _turns.add(_Turn(fromUser: true, text: question));
      _busy = true;
    });
    _scrollToEnd();

    try {
      final reply = await services.assistant.ask(
        context: services.session,
        question: question,
      );
      if (!mounted) return;
      setState(() {
        _turns.add(_Turn(
          fromUser: false,
          text: reply.answer,
          sources: reply.sources,
          grounded: reply.grounded,
          latency: reply.latency,
          noteId: reply.createdNote?.id,
        ));
      });
    } on AppException catch (error) {
      if (!mounted) return;
      setState(() {
        _turns.add(_Turn(fromUser: false, text: error.message, isError: true));
      });
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        if (_turns.isEmpty)
          Expanded(child: _buildEmptyState())
        else
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                  itemCount: _turns.length,
                  itemBuilder: (_, i) => _buildTurn(_turns[i]),
                ),
              ),
            ),
          ),
        _buildComposer(),
      ],
    );
  }

  Widget _buildHeader() {
    final health = _health;
    final llmOk = health?.reachable ?? false;
    final modelOk = health?.hasModel(AppConfig.chatModel) ?? false;

    return Container(
      padding: const EdgeInsets.fromLTRB(32, 14, 32, 15),
      decoration: const BoxDecoration(
        color: WorkspaceColors.surfaceCard,
        border: Border(bottom: BorderSide(color: WorkspaceColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Assistant',
                        style: TextStyle(
                            fontFamily: AppTheme.displayFamily,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: WorkspaceColors.textPrimary)),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: WorkspaceColors.accentViolet
                            .withValues(alpha: 0.15),
                        border: Border.all(
                            color: WorkspaceColors.accentViolet
                                .withValues(alpha: 0.4)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('V${AppConstants.appVersion}',
                          style: AppTheme.mono.copyWith(
                              fontSize: 11,
                              color: WorkspaceColors.accentViolet)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text('Forensic AI query engine over indexed case records',
                    style: TextStyle(
                        fontSize: 11, color: WorkspaceColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          if (_checking)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _pill(
                  label: llmOk ? 'Ollama connected' : 'Ollama unreachable',
                  color: llmOk
                      ? WorkspaceColors.accentEmerald
                      : WorkspaceColors.accentRose,
                  icon: llmOk ? Icons.check_circle_outline : Icons.cloud_off,
                ),
                if (llmOk)
                  _pill(
                    label: modelOk
                        ? AppConfig.chatModel
                        : '${AppConfig.chatModel} not pulled',
                    color: modelOk
                        ? WorkspaceColors.accentEmerald
                        : WorkspaceColors.accentAmber,
                    icon: Icons.memory,
                  ),
                _pill(
                  label: _indexNotice ?? 'Index not built',
                  color: _indexReady
                      ? WorkspaceColors.textSecondary
                      : WorkspaceColors.textMuted,
                  icon: Icons.travel_explore,
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _buildIndex,
                  icon: const Icon(Icons.refresh, size: 14),
                  label: Text(_indexReady ? 'Rebuild Index' : 'Build Index'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: WorkspaceColors.textPrimary,
                    side: const BorderSide(color: WorkspaceColors.border),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _pill({
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    const samples = [
      'Who is the most connected person in this network?',
      'Show me unusual financial activity for Sunita Rao.',
      'What links Ravi Deshmukh and Imran Shaikh?',
      'What is Zenith Impex?',
    ];

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Container(
            padding: const EdgeInsets.all(25),
            decoration: BoxDecoration(
              color: WorkspaceColors.surfaceCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: WorkspaceColors.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: WorkspaceColors.accentViolet.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: WorkspaceColors.accentViolet
                            .withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.forum_outlined,
                      size: 20, color: WorkspaceColors.accentViolet),
                ),
                const SizedBox(height: 12),
                const Text('Ask about the case database',
                    style: TextStyle(
                        fontFamily: AppTheme.displayFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: WorkspaceColors.textPrimary)),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 512),
                  child: const Text(
                    'Answers are synthesized strictly from indexed records and the '
                    'audit log. Every assertion carries an immutable source reference.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: WorkspaceColors.textSecondary,
                        fontSize: 12,
                        height: 1.5),
                  ),
                ),
                const SizedBox(height: 16),
                if (!_indexReady)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: WorkspaceColors.accentAmber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: WorkspaceColors.accentAmber
                              .withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 18, color: WorkspaceColors.accentAmber),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'The search index has not been built yet. Use "Build '
                            'index" above - it embeds every record locally and '
                            'takes a few seconds.',
                            style: TextStyle(
                                color: WorkspaceColors.textSecondary,
                                fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final sample in samples)
                        OutlinedButton(
                          onPressed: () {
                            _input.text = sample;
                            _send();
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: WorkspaceColors.textPrimary,
                            backgroundColor: WorkspaceColors.inputBackground,
                            side:
                                const BorderSide(color: WorkspaceColors.border),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text(sample,
                              style: const TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTurn(_Turn turn) {
    if (turn.fromUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 14, left: 60),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: WorkspaceColors.primary.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: WorkspaceColors.primary.withValues(alpha: 0.35)),
          ),
          child: Text(turn.text,
              style: const TextStyle(color: WorkspaceColors.textPrimary)),
        ),
      );
    }

    final accent = turn.isError
        ? WorkspaceColors.textMuted
        : (turn.grounded
            ? WorkspaceColors.accentViolet
            : WorkspaceColors.textMuted);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16, right: 60),
        decoration: BoxDecoration(
          color: WorkspaceColors.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: WorkspaceColors.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: accent),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 20, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _pill(
                              label: turn.isError
                                  ? 'UNAVAILABLE'
                                  : (turn.grounded
                                      ? 'GROUNDED ANSWER'
                                      : 'NO MATCH FOUND'),
                              color: accent,
                              icon: turn.isError
                                  ? Icons.error_outline
                                  : (turn.grounded
                                      ? Icons.auto_awesome
                                      : Icons.help_outline),
                            ),
                            if (turn.latency != null) ...[
                              const Spacer(),
                              Text(
                                'Latency: ${(turn.latency!.inMilliseconds)}ms',
                                style: AppTheme.mono.copyWith(
                                    fontSize: 11,
                                    color: WorkspaceColors.textMuted),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 10),
                        SelectableText(
                          turn.text,
                          style: const TextStyle(
                              color: WorkspaceColors.textPrimary, height: 1.55),
                        ),
                        if (turn.noteId != null) ...[
                          const SizedBox(height: 10),
                          _pill(
                            label: 'Case note ${turn.noteId} saved',
                            color: WorkspaceColors.accentEmerald,
                            icon: Icons.note_add_outlined,
                          ),
                        ],
                        if (turn.sources.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          const Divider(
                              height: 1, color: WorkspaceColors.border),
                          const SizedBox(height: 10),
                          const Text(
                            'SOURCES',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                              color: WorkspaceColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final source in turn.sources)
                                Tooltip(
                                  message: '${source.sourceType} - '
                                      'similarity ${source.score.toStringAsFixed(3)}',
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: WorkspaceColors.surfaceElevated,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: WorkspaceColors.border),
                                    ),
                                    child: Text(
                                      source.sourceId,
                                      style: AppTheme.mono.copyWith(
                                        fontSize: 11,
                                        color: WorkspaceColors.primary,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 12, 32, 16),
      decoration: const BoxDecoration(
        color: WorkspaceColors.surfaceCard,
        border: Border(top: BorderSide(color: WorkspaceColors.border)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: WorkspaceColors.inputBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: WorkspaceColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    enabled: !_busy,
                    onSubmitted: (_) => _send(),
                    style: const TextStyle(
                        fontSize: 14, color: WorkspaceColors.textPrimary),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      hintText: _indexReady
                          ? 'Ask about a subject, an account, or verify audit logs...'
                          : 'Build the search index before asking questions',
                      hintStyle: const TextStyle(
                          color: WorkspaceColors.textMuted, fontSize: 14),
                      prefixIcon: const Icon(Icons.search,
                          size: 18, color: WorkspaceColors.textMuted),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 32,
                  height: 32,
                  child: FilledButton(
                    onPressed: _busy ? null : _send,
                    style: FilledButton.styleFrom(
                      backgroundColor: WorkspaceColors.primary,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black),
                          )
                        : const Icon(Icons.send, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
