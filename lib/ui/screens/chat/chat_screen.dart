import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
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
        if (_turns.isEmpty) Expanded(child: _buildEmptyState()) else
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              itemCount: _turns.length,
              itemBuilder: (_, i) => _buildTurn(_turns[i]),
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
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Text('Assistant', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(width: 14),
          if (_checking)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else ...[
            _pill(
              label: llmOk ? 'Ollama connected' : 'Ollama unreachable',
              color: llmOk ? AppColors.accentEmerald : AppColors.accentRose,
              icon: llmOk ? Icons.check_circle_outline : Icons.cloud_off,
            ),
            const SizedBox(width: 8),
            if (llmOk)
              _pill(
                label: modelOk
                    ? AppConfig.chatModel
                    : '${AppConfig.chatModel} not pulled',
                color: modelOk ? AppColors.primary : AppColors.accentAmber,
                icon: Icons.memory,
              ),
            const SizedBox(width: 8),
            _pill(
              label: _indexNotice ?? 'Index not built',
              color: _indexReady ? AppColors.accentPurple : AppColors.textMuted,
              icon: Icons.travel_explore,
            ),
          ],
          const Spacer(),
          TextButton.icon(
            onPressed: _busy ? null : _buildIndex,
            icon: const Icon(Icons.refresh, size: 16),
            label: Text(_indexReady ? 'Rebuild index' : 'Build index'),
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.forum_outlined,
                size: 40, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text('Ask about the case database',
                style: Theme.of(context).textTheme.displayMedium),
            const SizedBox(height: 8),
            const Text(
              'Answers come only from the indexed records and audit log, and '
              'cite the record ids they used. If nothing relevant is found, '
              'the assistant says so rather than guessing.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 22),
            if (!_indexReady)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.accentAmber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.accentAmber.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 18, color: AppColors.accentAmber),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'The search index has not been built yet. Use "Build '
                        'index" above - it embeds every record locally and '
                        'takes a few seconds.',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final sample in samples)
                    ActionChip(
                      label: Text(sample,
                          style: const TextStyle(fontSize: 12)),
                      onPressed: () {
                        _input.text = sample;
                        _send();
                      },
                    ),
                ],
              ),
          ],
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
            color: AppColors.primary.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
          ),
          child: Text(turn.text,
              style: const TextStyle(color: AppColors.textPrimary)),
        ),
      );
    }

    final accent = turn.isError
        ? AppColors.accentRose
        : (turn.grounded ? AppColors.accentPurple : AppColors.accentAmber);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16, right: 60),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  turn.isError
                      ? Icons.error_outline
                      : (turn.grounded
                          ? Icons.auto_awesome
                          : Icons.help_outline),
                  size: 15,
                  color: accent,
                ),
                const SizedBox(width: 7),
                Text(
                  turn.isError
                      ? 'Unavailable'
                      : (turn.grounded ? 'Grounded answer' : 'No match'),
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: accent),
                ),
                if (turn.latency != null) ...[
                  const Spacer(),
                  Text(
                    '${(turn.latency!.inMilliseconds / 1000).toStringAsFixed(1)}s',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(
              turn.text,
              style: const TextStyle(color: AppColors.textPrimary, height: 1.55),
            ),
            if (turn.noteId != null) ...[
              const SizedBox(height: 10),
              _pill(
                label: 'Case note ${turn.noteId} saved',
                color: AppColors.accentEmerald,
                icon: Icons.note_add_outlined,
              ),
            ],
            if (turn.sources.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Divider(height: 1, color: AppColors.border),
              const SizedBox(height: 10),
              const Text(
                'SOURCES',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: AppColors.textMuted,
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
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          source.sourceId,
                          style: AppTheme.mono.copyWith(
                            fontSize: 11,
                            color: AppColors.primary,
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
    );
  }

  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              enabled: !_busy,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: _indexReady
                    ? 'Ask about a subject, a transaction, or the audit trail...'
                    : 'Build the search index before asking questions',
                prefixIcon: const Icon(Icons.search, size: 18),
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: _busy ? null : _send,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
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
        ],
      ),
    );
  }
}
