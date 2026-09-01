/// Provider-agnostic contract for the local language model.
///
/// `docs/Rules.md` §17 requires all LLM access to go through this interface
/// with a configurable base URL, so moving inference to a stronger machine on
/// the LAN is a config change rather than a code change. Nothing outside
/// `lib/llm/` may talk to a model over HTTP directly.
library;

/// Who authored a turn in a conversation.
enum LlmRole {
  system,
  user,
  assistant,

  /// The result of a tool the model asked to run, fed back to it.
  tool;

  String get wireName => name;
}

/// One conversation turn.
class LlmMessage {
  final LlmRole role;
  final String content;

  /// Name of the tool this message reports the result of. Set only when
  /// [role] is [LlmRole.tool].
  final String? toolName;

  const LlmMessage({
    required this.role,
    required this.content,
    this.toolName,
  });

  const LlmMessage.system(this.content)
      : role = LlmRole.system,
        toolName = null;

  const LlmMessage.user(this.content)
      : role = LlmRole.user,
        toolName = null;

  const LlmMessage.assistant(this.content)
      : role = LlmRole.assistant,
        toolName = null;

  const LlmMessage.toolResult({required String tool, required this.content})
      : role = LlmRole.tool,
        toolName = tool;

  Map<String, dynamic> toWire() => {
        'role': role.wireName,
        'content': content,
        if (toolName != null) 'name': toolName,
      };
}

/// A tool the model is allowed to call, described to it in JSON-Schema form.
///
/// The set of these handed to [LlmClient.chat] *is* the model's capability
/// surface — it cannot invoke anything not described here. See `ActionGuard`
/// for why that set has exactly one member.
class LlmToolSpec {
  final String name;
  final String description;

  /// JSON Schema for the tool's arguments object.
  final Map<String, dynamic> parameters;

  const LlmToolSpec({
    required this.name,
    required this.description,
    required this.parameters,
  });

  Map<String, dynamic> toWire() => {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': parameters,
        },
      };
}

/// A tool invocation requested by the model.
class LlmToolCall {
  final String name;
  final Map<String, dynamic> arguments;

  const LlmToolCall({required this.name, required this.arguments});

  @override
  String toString() => 'LlmToolCall($name, $arguments)';
}

/// A completed model response.
class LlmChatResponse {
  /// Natural-language content. May be empty when the model chose to call a
  /// tool instead of answering.
  final String content;

  /// Tools the model asked to run. Empty for a plain answer.
  final List<LlmToolCall> toolCalls;

  final String model;

  /// Wall-clock time for the request, used for the on-device latency numbers
  /// `docs/Rules.md` §21 requires us to actually measure.
  final Duration latency;

  final int? promptTokens;
  final int? completionTokens;

  const LlmChatResponse({
    required this.content,
    required this.model,
    required this.latency,
    this.toolCalls = const [],
    this.promptTokens,
    this.completionTokens,
  });

  bool get hasToolCalls => toolCalls.isNotEmpty;
}

/// Health snapshot of the model backend, for the diagnostics panel.
class LlmHealth {
  final bool reachable;
  final String baseUrl;
  final List<String> installedModels;
  final String? error;

  const LlmHealth({
    required this.reachable,
    required this.baseUrl,
    this.installedModels = const [],
    this.error,
  });

  bool hasModel(String model) => installedModels.any(
        (m) => m == model || m.split(':').first == model.split(':').first,
      );
}

/// The local model backend.
abstract interface class LlmClient {
  /// Where this client is pointed. Surfaced in diagnostics so it is obvious
  /// when inference has been offloaded to another machine.
  String get baseUrl;

  /// Model used for chat/answers.
  String get chatModel;

  /// Model used for embeddings.
  String get embedModel;

  /// Checks reachability and reports which models are installed.
  Future<LlmHealth> checkHealth();

  /// Runs a chat completion.
  ///
  /// When [tools] is non-empty the model may respond with tool calls instead
  /// of prose; inspect [LlmChatResponse.toolCalls].
  Future<LlmChatResponse> chat({
    required List<LlmMessage> messages,
    List<LlmToolSpec> tools = const [],
    double temperature = 0.1,
    String? model,
  });

  /// Embeds a single string.
  Future<List<double>> embed(String text, {String? model});

  /// Embeds several strings. Implementations may batch or loop; callers should
  /// prefer this over repeated [embed] calls when indexing.
  Future<List<List<double>>> embedAll(List<String> texts, {String? model});

  /// Releases any underlying connections.
  void dispose();
}
