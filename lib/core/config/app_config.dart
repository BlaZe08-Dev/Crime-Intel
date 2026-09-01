import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Runtime configuration.
///
/// `docs/Rules.md` §17 requires the LLM base URL to be configuration rather
/// than code, so inference can be moved to a LAN machine without a rebuild.
/// §14 requires secrets to live only in a local, git-ignored `.env`.
///
/// **Why `.env` is read from disk rather than bundled as an asset.** This is a
/// packaged desktop app: the investigator gets a folder, and the natural place
/// for their Plunk key is a `.env` sitting next to `crime_intel.exe` that they
/// can edit without rebuilding. Baking it into the asset bundle would mean the
/// key is compiled in, and would make a fresh clone fail to build whenever the
/// declared `.env` asset was missing. Load order:
///
/// 1. `.env` next to the executable  (what a packaged install uses)
/// 2. `.env` in the working directory (what `flutter run` uses)
/// 3. the bundled `.env.example`      (defaults, no secrets)
/// 4. the constants below
///
/// A missing or malformed file is never fatal — losing the whole app to a
/// config typo mid-demo is the wrong trade.
abstract final class AppConfig {
  static final Map<String, String> _values = {};
  static bool _loaded = false;
  static String _source = 'defaults';

  /// Where the values came from — shown in the diagnostics panel.
  static String get source => _source;

  // Defaults must stay in sync with .env.example.
  static const String _defaultOllamaBaseUrl = 'http://localhost:11434';
  static const String _defaultChatModel = 'granite4.1:3b';
  static const String _defaultEmbedModel = 'nomic-embed-text';

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;

    for (final file in _candidateFiles()) {
      try {
        if (!await file.exists()) continue;
        _values.addAll(_parse(await file.readAsString()));
        _source = file.path;
        return;
      } catch (_) {
        // Unreadable file: fall through to the next candidate.
      }
    }

    try {
      _values.addAll(_parse(await rootBundle.loadString('.env.example')));
      _source = '.env.example (bundled defaults)';
    } catch (_) {
      _source = 'defaults';
    }
  }

  static Iterable<File> _candidateFiles() sync* {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      yield File('$exeDir${Platform.pathSeparator}.env');
    } catch (_) {
      // resolvedExecutable is unavailable in some test hosts.
    }
    yield File('.env');
  }

  /// Minimal `KEY=VALUE` parser: ignores blanks and `#` comments, strips
  /// matching surrounding quotes.
  @visibleForTesting
  static Map<String, String> parse(String content) => _parse(content);

  static Map<String, String> _parse(String content) {
    final result = <String, String>{};
    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final separator = line.indexOf('=');
      if (separator <= 0) continue;

      final key = line.substring(0, separator).trim();
      var value = line.substring(separator + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      if (key.isNotEmpty) result[key] = value;
    }
    return result;
  }

  static String _read(String key, String fallback) {
    final value = _values[key];
    return (value == null || value.trim().isEmpty) ? fallback : value.trim();
  }

  static int _readInt(String key, int fallback) =>
      int.tryParse(_read(key, '')) ?? fallback;

  static double _readDouble(String key, double fallback) =>
      double.tryParse(_read(key, '')) ?? fallback;

  /// Base URL of the Ollama server. Point at a LAN host to offload inference.
  static String get ollamaBaseUrl =>
      _read('OLLAMA_BASE_URL', _defaultOllamaBaseUrl);

  /// Chat/answer model. IBM Granite 4.1 3B — Apache-2.0, RAG-oriented.
  static String get chatModel => _read('OLLAMA_MODEL', _defaultChatModel);

  /// Embedding model used to build and query the RAG index.
  static String get embedModel =>
      _read('OLLAMA_EMBED_MODEL', _defaultEmbedModel);

  /// Generation budget. Generous: a cold model is slow to first token.
  static Duration get llmTimeout =>
      Duration(seconds: _readInt('LLM_TIMEOUT_SECONDS', 180));

  static Duration get embedTimeout =>
      Duration(seconds: _readInt('EMBED_TIMEOUT_SECONDS', 60));

  /// Number of chunks handed to the model as grounding context.
  static int get retrievalTopK => _readInt('RAG_TOP_K', 6);

  /// Cosine similarity below which a chunk counts as irrelevant. If nothing
  /// clears it, the assistant must say "not in the database" instead of
  /// guessing (`docs/Rules.md` §4).
  static double get retrievalMinScore => _readDouble('RAG_MIN_SCORE', 0.35);

  /// Plunk key for the OTP fallback. Empty when unset; never committed.
  static String get plunkApiKey => _read('PLUNK_API_KEY', '');

  static bool get isPlunkConfigured => plunkApiKey.isNotEmpty;

  /// Non-secret summary for diagnostics. Never includes key material.
  static Map<String, String> describe() => {
        'configSource': _source,
        'ollamaBaseUrl': ollamaBaseUrl,
        'chatModel': chatModel,
        'embedModel': embedModel,
        'retrievalTopK': '$retrievalTopK',
        'retrievalMinScore': '$retrievalMinScore',
        'plunkConfigured': '$isPlunkConfigured',
      };

  @visibleForTesting
  static void overrideForTest(Map<String, String> values) {
    _values
      ..clear()
      ..addAll(values);
    _loaded = true;
    _source = 'test-override';
  }

  @visibleForTesting
  static void resetForTest() {
    _values.clear();
    _loaded = false;
    _source = 'defaults';
  }
}
