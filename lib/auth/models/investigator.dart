import 'dart:convert';

class Investigator {
  final String id;
  final String displayName;
  final String email;
  final List<List<double>> faceEmbeddings;
  final int createdAt;

  const Investigator({
    required this.id,
    required this.displayName,
    required this.email,
    this.faceEmbeddings = const [],
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'displayName': displayName,
      'email': email,
      'faceEmbeddings': jsonEncode(faceEmbeddings),
      'createdAt': createdAt,
    };
  }

  factory Investigator.fromMap(Map<String, dynamic> map) {
    List<List<double>> embeddings = [];
    if (map['faceEmbeddings'] != null) {
      try {
        final decoded = map['faceEmbeddings'] is String
            ? jsonDecode(map['faceEmbeddings'] as String)
            : map['faceEmbeddings'];
        if (decoded is List) {
          embeddings = decoded.map((innerList) {
            if (innerList is List) {
              return innerList.map((val) => (val as num).toDouble()).toList();
            }
            return <double>[];
          }).toList();
        }
      } catch (_) {
        embeddings = [];
      }
    }

    return Investigator(
      id: map['id'] as String,
      displayName: map['displayName'] as String,
      email: map['email'] as String,
      faceEmbeddings: embeddings,
      createdAt: (map['createdAt'] as num).toInt(),
    );
  }
}
