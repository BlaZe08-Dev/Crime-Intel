import 'dart:math' as math;

import 'package:crime_intel/llm/llm_client.dart';

/// Deterministic stand-in for Ollama.
///
/// Lets the RAG and assistant tests assert real behaviour — grounding,
/// citation, the tool boundary — without a model server running, so the suite
/// stays fast and passes in CI.
class FakeLlmClient implements LlmClient {
  /// Replies returned in order; the last is reused once exhausted.
  final List<LlmChatResponse> scriptedReplies;

  /// Every request this client received, for assertions.
  final List<List<LlmMessage>> receivedMessages = [];
  final List<List<LlmToolSpec>> receivedTools = [];

  int _replyIndex = 0;

  FakeLlmClient({this.scriptedReplies = const []});

  /// Convenience constructor for a single plain-text answer.
  factory FakeLlmClient.answering(String answer) => FakeLlmClient(
        scriptedReplies: [
          LlmChatResponse(
            content: answer,
            model: 'fake',
            latency: Duration.zero,
          ),
        ],
      );

  @override
  String get baseUrl => 'fake://local';

  @override
  String get chatModel => 'fake-chat';

  @override
  String get embedModel => 'fake-embed';

  @override
  Future<LlmHealth> checkHealth() async => const LlmHealth(
        reachable: true,
        baseUrl: 'fake://local',
        installedModels: ['fake-chat', 'fake-embed'],
      );

  @override
  Future<LlmChatResponse> chat({
    required List<LlmMessage> messages,
    List<LlmToolSpec> tools = const [],
    double temperature = 0.1,
    String? model,
  }) async {
    receivedMessages.add(messages);
    receivedTools.add(tools);

    if (scriptedReplies.isEmpty) {
      return const LlmChatResponse(
        content: 'no scripted reply',
        model: 'fake',
        latency: Duration.zero,
      );
    }
    final reply =
        scriptedReplies[math.min(_replyIndex, scriptedReplies.length - 1)];
    _replyIndex++;
    return reply;
  }

  /// Deterministic bag-of-words embedding.
  ///
  /// Not semantic, but stable and similarity-ordered for shared vocabulary,
  /// which is all the retrieval tests need.
  @override
  Future<List<double>> embed(String text, {String? model}) async {
    const dimensions = 64;
    final vector = List<double>.filled(dimensions, 0);
    for (final word in text.toLowerCase().split(RegExp(r'[^a-z0-9]+'))) {
      if (word.isEmpty) continue;
      vector[word.hashCode.abs() % dimensions] += 1;
    }
    return vector;
  }

  @override
  Future<List<List<double>>> embedAll(List<String> texts, {String? model}) async {
    return [for (final text in texts) await embed(text)];
  }

  @override
  void dispose() {}
}
