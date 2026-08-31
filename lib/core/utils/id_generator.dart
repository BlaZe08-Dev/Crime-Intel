import 'package:uuid/uuid.dart';

class IdGenerator {
  static const _uuid = Uuid();

  /// Generates a UUID v4 string.
  static String generate([String? prefix]) {
    final id = _uuid.v4();
    if (prefix != null && prefix.isNotEmpty) {
      return '$prefix-$id';
    }
    return id;
  }
}
