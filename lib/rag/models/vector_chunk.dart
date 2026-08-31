import 'dart:convert';

class VectorChunk {
  final String id;
  final String sourceType;
  final String sourceId;
  final String text;
  final List<double> embedding;

  const VectorChunk({
    required this.id,
    required this.sourceType,
    required this.sourceId,
    required this.text,
    this.embedding = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sourceType': sourceType,
      'sourceId': sourceId,
      'text': text,
      'embedding': jsonEncode(embedding),
    };
  }

  factory VectorChunk.fromMap(Map<String, dynamic> map) {
    List<double> parsedEmbedding = [];
    if (map['embedding'] != null) {
      try {
        final decoded = map['embedding'] is String
            ? jsonDecode(map['embedding'] as String)
            : map['embedding'];
        if (decoded is List) {
          parsedEmbedding = decoded.map((e) => (e as num).toDouble()).toList();
        }
      } catch (_) {
        parsedEmbedding = [];
      }
    }

    return VectorChunk(
      id: map['id'] as String,
      sourceType: map['sourceType'] as String,
      sourceId: map['sourceId'] as String,
      text: map['text'] as String,
      embedding: parsedEmbedding,
    );
  }
}
