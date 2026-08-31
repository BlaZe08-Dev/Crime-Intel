import 'dart:convert';
import 'package:crypto/crypto.dart';

class CryptoUtils {
  /// Computes the SHA-256 hex digest of any UTF-8 string.
  static String sha256Hash(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Computes a deterministic SHA-256 hash for a structured JSON/Map payload.
  static String hashPayload(Map<String, dynamic>? payload) {
    if (payload == null || payload.isEmpty) {
      return sha256Hash('{}');
    }
    // Sort keys recursively for deterministic payload hashing
    final canonicalJson = _canonicalJson(payload);
    return sha256Hash(canonicalJson);
  }

  static String _canonicalJson(dynamic object) {
    if (object is Map) {
      final sortedKeys = object.keys.map((k) => k.toString()).toList()..sort();
      final mapEntries = sortedKeys.map((k) {
        return '"$k":${_canonicalJson(object[k])}';
      }).join(',');
      return '{$mapEntries}';
    } else if (object is List) {
      final listEntries = object.map((e) => _canonicalJson(e)).join(',');
      return '[$listEntries]';
    } else if (object is String) {
      return jsonEncode(object);
    } else {
      return '$object';
    }
  }
}
