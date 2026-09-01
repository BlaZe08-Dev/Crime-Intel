import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';
import '../core/errors/app_exceptions.dart';
import 'llm_client.dart';

/// [LlmClient] backed by a local Ollama server (`docs/TechSpec.md` §2.2).
///
/// Everything runs against [baseUrl], which comes from `OLLAMA_BASE_URL` and
/// defaults to `http://localhost:11434`. No hosted API is contacted on any
/// path (`docs/Rules.md` §7).
class OllamaClient implements LlmClient {
  final http.Client _http;
  final String _baseUrl;
  final String _chatModel;
  final String _embedModel;
  final Duration _chatTimeout;
  final Duration _embedTimeout;

  /// Set once we learn which embeddings endpoint this server speaks, so we
  /// stop paying for the probe on every call.
  bool? _supportsBatchEmbed;

  OllamaClient({
    http.Client? httpClient,
    String? baseUrl,
    String? chatModel,
    String? embedModel,
    Duration? chatTimeout,
    Duration? embedTimeout,
  })  : _http = httpClient ?? http.Client(),
        _baseUrl = (baseUrl ?? AppConfig.ollamaBaseUrl).replaceAll(
          RegExp(r'/+$'),
          '',
        ),
        _chatModel = chatModel ?? AppConfig.chatModel,
        _embedModel = embedModel ?? AppConfig.embedModel,
        _chatTimeout = chatTimeout ?? AppConfig.llmTimeout,
        _embedTimeout = embedTimeout ?? AppConfig.embedTimeout;

  @override
  String get baseUrl => _baseUrl;

  @override
  String get chatModel => _chatModel;

  @override
  String get embedModel => _embedModel;

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  /// Maps transport-level failures onto our typed exceptions so the UI can
  /// render something actionable instead of a raw SocketException.
  Never _rethrowAsAppException(Object error, StackTrace stackTrace) {
    if (error is AppException) throw error;
    if (error is TimeoutException) throw LlmTimeoutException(_chatTimeout);
    if (error is SocketException || error is http.ClientException) {
      throw LlmUnavailableException(_baseUrl, cause: error);
    }
    throw LlmRequestException(
      'Unexpected failure talking to the model server.',
      cause: error,
    );
  }

  @override
  Future<LlmHealth> checkHealth() async {
    try {
      final response = await _http
          .get(_uri('/api/tags'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return LlmHealth(
          reachable: false,
          baseUrl: _baseUrl,
          error: 'Server returned HTTP ${response.statusCode}.',
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final models = (decoded['models'] as List<dynamic>? ?? const [])
          .map((m) => (m as Map<String, dynamic>)['name'] as String? ?? '')
          .where((name) => name.isNotEmpty)
          .toList();

      return LlmHealth(
        reachable: true,
        baseUrl: _baseUrl,
        installedModels: models,
      );
    } catch (error) {
      return LlmHealth(
        reachable: false,
        baseUrl: _baseUrl,
        error: 'Cannot reach Ollama at $_baseUrl. Is it running?',
      );
    }
  }

  @override
  Future<LlmChatResponse> chat({
    required List<LlmMessage> messages,
    List<LlmToolSpec> tools = const [],
    double temperature = 0.1,
    String? model,
  }) async {
    final targetModel = model ?? _chatModel;
    final stopwatch = Stopwatch()..start();

    final body = <String, dynamic>{
      'model': targetModel,
      'messages': messages.map((m) => m.toWire()).toList(),
      'stream': false,
      'options': {
        // Low temperature: answers must track the retrieved records, not
        // wander (`docs/Rules.md` §4).
        'temperature': temperature,
      },
      if (tools.isNotEmpty) 'tools': tools.map((t) => t.toWire()).toList(),
    };

    try {
      final response = await _http
          .post(
            _uri('/api/chat'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_chatTimeout);

      stopwatch.stop();

      if (response.statusCode == 404) {
        throw LlmModelMissingException(targetModel);
      }
      if (response.statusCode != 200) {
        throw LlmRequestException(
          _describeHttpFailure(response, targetModel),
          statusCode: response.statusCode,
        );
      }

      final decoded =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final message = decoded['message'] as Map<String, dynamic>? ?? const {};

      return LlmChatResponse(
        content: (message['content'] as String? ?? '').trim(),
        toolCalls: _parseToolCalls(message['tool_calls']),
        model: decoded['model'] as String? ?? targetModel,
        latency: stopwatch.elapsed,
        promptTokens: (decoded['prompt_eval_count'] as num?)?.toInt(),
        completionTokens: (decoded['eval_count'] as num?)?.toInt(),
      );
    } catch (error, stackTrace) {
      _rethrowAsAppException(error, stackTrace);
    }
  }

  /// Ollama reports a missing model as a 404 or as a 400 mentioning it; both
  /// deserve the "pull it" message rather than a generic failure.
  String _describeHttpFailure(http.Response response, String model) {
    final raw = response.body.toLowerCase();
    if (raw.contains('not found') || raw.contains('no such model')) {
      return 'Model "$model" is not installed. Run:  ollama pull $model';
    }
    if (raw.contains('memory')) {
      return 'The model server ran out of memory loading "$model". '
          'Close other applications, or use a smaller model.';
    }
    return 'Model server returned HTTP ${response.statusCode}.';
  }

  List<LlmToolCall> _parseToolCalls(Object? raw) {
    if (raw is! List) return const [];
    final calls = <LlmToolCall>[];

    for (final item in raw) {
      if (item is! Map<String, dynamic>) continue;
      final fn = item['function'];
      if (fn is! Map<String, dynamic>) continue;

      final name = fn['name'] as String?;
      if (name == null || name.isEmpty) continue;

      // Ollama sends arguments as an object, but some model templates emit a
      // JSON string. Accept both rather than dropping the call.
      final rawArgs = fn['arguments'];
      Map<String, dynamic> args = const {};
      if (rawArgs is Map<String, dynamic>) {
        args = rawArgs;
      } else if (rawArgs is String && rawArgs.trim().isNotEmpty) {
        try {
          final parsed = jsonDecode(rawArgs);
          if (parsed is Map<String, dynamic>) args = parsed;
        } catch (_) {
          // Unparseable arguments: keep the call with empty args so the guard
          // rejects it explicitly instead of it vanishing silently.
        }
      }

      calls.add(LlmToolCall(name: name, arguments: args));
    }

    return calls;
  }

  @override
  Future<List<double>> embed(String text, {String? model}) async {
    final vectors = await embedAll([text], model: model);
    return vectors.isEmpty ? const <double>[] : vectors.first;
  }

  @override
  Future<List<List<double>>> embedAll(
    List<String> texts, {
    String? model,
  }) async {
    if (texts.isEmpty) return const [];
    final targetModel = model ?? _embedModel;

    // Prefer /api/embed (batched, current). Older servers only have
    // /api/embeddings, which is one string per request.
    //
    // The fallback is deliberately narrow. Retrying a down server or a missing
    // model once per chunk would turn one clear failure into a hundred slow
    // ones, so only "this server does not have that endpoint" downgrades.
    if (_supportsBatchEmbed ?? true) {
      try {
        final vectors = await _embedBatch(texts, targetModel);
        _supportsBatchEmbed = true;
        return vectors;
      } on LlmModelMissingException {
        rethrow;
      } on LlmRequestException catch (error) {
        if (error.statusCode != null && error.statusCode != 404) rethrow;
        _supportsBatchEmbed = false;
      } on SocketException catch (error) {
        throw LlmUnavailableException(_baseUrl, cause: error);
      } on http.ClientException catch (error) {
        throw LlmUnavailableException(_baseUrl, cause: error);
      } on TimeoutException {
        throw LlmTimeoutException(_embedTimeout);
      }
    }

    final results = <List<double>>[];
    for (final text in texts) {
      results.add(await _embedSingle(text, targetModel));
    }
    return results;
  }

  Future<List<List<double>>> _embedBatch(
    List<String> texts,
    String model,
  ) async {
    final response = await _http
        .post(
          _uri('/api/embed'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'model': model, 'input': texts}),
        )
        .timeout(_embedTimeout);

    if (response.statusCode == 404) {
      // Distinguish "endpoint absent" (old server) from "model absent".
      if (response.body.toLowerCase().contains('model')) {
        throw LlmModelMissingException(model);
      }
      throw const LlmRequestException('Batch embed endpoint unavailable.');
    }
    if (response.statusCode != 200) {
      throw LlmRequestException(
        _describeHttpFailure(response, model),
        statusCode: response.statusCode,
      );
    }

    final decoded =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final embeddings = decoded['embeddings'];
    if (embeddings is! List) {
      throw const LlmRequestException('Embed response had no embeddings.');
    }

    return embeddings
        .map<List<double>>((row) => (row as List<dynamic>)
            .map<double>((v) => (v as num).toDouble())
            .toList())
        .toList();
  }

  Future<List<double>> _embedSingle(String text, String model) async {
    try {
      final response = await _http
          .post(
            _uri('/api/embeddings'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'model': model, 'prompt': text}),
          )
          .timeout(_embedTimeout);

      if (response.statusCode == 404) throw LlmModelMissingException(model);
      if (response.statusCode != 200) {
        throw LlmRequestException(
          _describeHttpFailure(response, model),
          statusCode: response.statusCode,
        );
      }

      final decoded =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final embedding = decoded['embedding'];
      if (embedding is! List) {
        throw const LlmRequestException('Embed response had no embedding.');
      }
      return embedding.map<double>((v) => (v as num).toDouble()).toList();
    } catch (error, stackTrace) {
      _rethrowAsAppException(error, stackTrace);
    }
  }

  @override
  void dispose() => _http.close();
}
