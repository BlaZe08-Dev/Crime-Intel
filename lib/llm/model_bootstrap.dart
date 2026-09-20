import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../audit/audit_logger.dart';
import '../audit/models/log_entry.dart';
import '../core/security/actor_context.dart';

/// The only definition of the Ollama models CrimeIntel requires.
///
/// Keep these names exact: `/api/tags` returns tagged names and bootstrap must
/// not treat a similarly named tag as satisfying the release requirement.
abstract final class RequiredOllamaModels {
  static const String chat = 'granite4.1:3b';
  static const String embedding = 'nomic-embed-text';

  static const List<String> all = [chat, embedding];
}

enum ModelBootstrapPhase {
  checking,
  startingDaemon,
  pulling,
  ready,
  failed,
  fatal
}

class ModelBootstrapState {
  final ModelBootstrapPhase phase;
  final String? model;
  final int modelIndex;
  final int completedBytes;
  final int totalBytes;
  final String status;
  final String? error;

  const ModelBootstrapState({
    required this.phase,
    this.model,
    this.modelIndex = 0,
    this.completedBytes = 0,
    this.totalBytes = 0,
    this.status = '',
    this.error,
  });

  double get progress =>
      totalBytes == 0 ? 0 : (completedBytes / totalBytes).clamp(0.0, 1.0);
}

/// Ensures the locally installed Ollama runtime has CrimeIntel's two models.
///
/// Pulls use Ollama's HTTP NDJSON protocol rather than scraping `ollama pull`,
/// which gives the UI accurate layer status and resumable byte progress.
class ModelBootstrap extends ChangeNotifier {
  final AuditLogger _audit;
  final Uri _baseUri;
  final Duration daemonTimeout;
  http.Client? _activeClient;
  bool _cancelled = false;

  ModelBootstrap({
    required AuditLogger audit,
    Uri? baseUri,
    this.daemonTimeout = const Duration(seconds: 30),
  })  : _audit = audit,
        _baseUri = baseUri ?? Uri.parse('http://127.0.0.1:11434');

  ModelBootstrapState _state = const ModelBootstrapState(
    phase: ModelBootstrapPhase.checking,
    status: 'Checking the local AI service…',
  );
  ModelBootstrapState get state => _state;

  Uri _uri(String path) => _baseUri.replace(path: path);

  void _set(ModelBootstrapState value) {
    _state = value;
    notifyListeners();
  }

  /// Stops the current HTTP stream. Ollama retains partial blobs, so a retry
  /// simply issues another `/api/pull` request.
  void cancel() {
    _cancelled = true;
    _activeClient?.close();
  }

  /// Cheap preflight used before rendering the bootstrap page. This is what
  /// prevents that page from flashing on machines where both tags are present.
  Future<bool> requiredModelsPresent() async {
    final installed = await _tags();
    return installed != null &&
        RequiredOllamaModels.all.every(installed.contains);
  }

  Future<bool> ensureModels() async {
    _cancelled = false;
    try {
      var installed = await _tags();
      if (installed == null) {
        final hasBinary = await _ollamaBinaryExists();
        if (!hasBinary) {
          _set(const ModelBootstrapState(
            phase: ModelBootstrapPhase.fatal,
            status: 'Ollama is not installed.',
            error: 'CrimeIntel could not reach Ollama and the `ollama` command '
                'is not installed. Reinstall the CrimeIntel .deb package or run '
                'scripts/setup.sh, then launch the app again.',
          ));
          return false;
        }

        _set(const ModelBootstrapState(
          phase: ModelBootstrapPhase.startingDaemon,
          status: 'Starting the Ollama service…',
        ));
        await _startDaemon();
        installed = await _waitForTags();
        if (installed == null) {
          throw StateError('Ollama is installed but did not answer at '
              '${_baseUri.toString()} within ${daemonTimeout.inSeconds} seconds. '
              'Start it with `ollama serve` and retry.');
        }
      }

      for (var index = 0; index < RequiredOllamaModels.all.length; index++) {
        final model = RequiredOllamaModels.all[index];
        if (installed.contains(model)) continue;
        await _pull(model, index);
        final verifiedInstalled = await _tags();
        if (verifiedInstalled == null || !verifiedInstalled.contains(model)) {
          await _logPullFailed(
              model, 'Model was absent from /api/tags after pull.');
          throw StateError(
              'Ollama reported a successful pull, but model "$model" '
              'is not listed by /api/tags.');
        }
        await _audit.log(
          context: const SystemContext(),
          action: LogAction.MODEL_PULL_COMPLETED,
          targetType: 'OllamaModel',
          targetId: model,
          payload: {'model': model},
        );
      }

      _set(const ModelBootstrapState(
        phase: ModelBootstrapPhase.ready,
        status: 'AI models are ready.',
      ));
      return true;
    } catch (error) {
      if (_cancelled) {
        _set(const ModelBootstrapState(
          phase: ModelBootstrapPhase.failed,
          status: 'Download cancelled.',
          error: 'The model download was cancelled. Partial data was kept by '
              'Ollama and will resume when you retry.',
        ));
      } else {
        _set(ModelBootstrapState(
          phase: ModelBootstrapPhase.failed,
          status: 'Model setup failed.',
          error: error.toString(),
        ));
      }
      return false;
    } finally {
      _activeClient?.close();
      _activeClient = null;
    }
  }

  Future<Set<String>?> _tags() async {
    final client = http.Client();
    try {
      final response = await client
          .get(_uri('/api/tags'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) return null;
      return (decoded['models'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((entry) => entry['name'] as String? ?? '')
          .where((name) => name.isNotEmpty)
          .toSet();
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  Future<Set<String>?> _waitForTags() async {
    final deadline = DateTime.now().add(daemonTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final tags = await _tags();
      if (tags != null) return tags;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return null;
  }

  Future<bool> _ollamaBinaryExists() async {
    try {
      final result = await Process.run('ollama', ['--version']);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  Future<void> _startDaemon() async {
    try {
      await Process.run('systemctl', ['start', 'ollama'])
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // A non-systemd desktop can still host a detached local daemon.
    }
    if (await _tags() != null) return;
    try {
      await Process.start('ollama', ['serve'], mode: ProcessStartMode.detached);
    } on ProcessException {
      // `_waitForTags` produces the actionable error if this did not work.
    }
  }

  Future<void> _pull(String model, int modelIndex) async {
    await _audit.log(
      context: const SystemContext(),
      action: LogAction.MODEL_PULL_STARTED,
      targetType: 'OllamaModel',
      targetId: model,
      payload: {'model': model},
    );

    final layerTotals = <String, int>{};
    final layerCompleted = <String, int>{};
    try {
      final client = http.Client();
      _activeClient = client;
      final request = http.Request('POST', _uri('/api/pull'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({'model': model, 'stream': true});
      final response = await client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await response.stream.bytesToString();
        throw HttpException(
            'Ollama returned HTTP ${response.statusCode}: $body');
      }

      await for (final line in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (_cancelled) throw StateError('Download cancelled.');
        if (line.trim().isEmpty) {
          continue;
        }
        final event = jsonDecode(line);
        if (event is! Map<String, dynamic>) {
          continue;
        }
        if (event['error'] != null) {
          throw StateError(event['error'].toString());
        }

        final digest = event['digest'] as String?;
        final total = (event['total'] as num?)?.toInt();
        final completed = (event['completed'] as num?)?.toInt();
        if (digest != null && total != null) {
          layerTotals[digest] = total;
        }
        if (digest != null && completed != null) {
          layerCompleted[digest] = completed;
        }
        final totalBytes = layerTotals.values.fold<int>(0, (a, b) => a + b);
        final completedBytes = layerCompleted.entries.fold<int>(0, (sum, item) {
          final max = layerTotals[item.key] ?? item.value;
          return sum + item.value.clamp(0, max).toInt();
        });
        _set(ModelBootstrapState(
          phase: ModelBootstrapPhase.pulling,
          model: model,
          modelIndex: modelIndex,
          completedBytes: completedBytes,
          totalBytes: totalBytes,
          status: event['status'] as String? ?? 'Downloading…',
        ));
      }
      if (_cancelled) throw StateError('Download cancelled.');
    } catch (error) {
      await _logPullFailed(model, error.toString());
      rethrow;
    }
  }

  Future<void> _logPullFailed(String model, String error) => _audit.log(
        context: const SystemContext(),
        action: LogAction.MODEL_PULL_FAILED,
        targetType: 'OllamaModel',
        targetId: model,
        payload: {'model': model, 'error': error},
      );
}
