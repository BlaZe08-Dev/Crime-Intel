enum NoteAuthor {
  INVESTIGATOR,
  ASSISTANT;

  String get displayName {
    switch (this) {
      case NoteAuthor.INVESTIGATOR:
        return 'Investigator';
      case NoteAuthor.ASSISTANT:
        return 'AI Assistant';
    }
  }

  static NoteAuthor fromString(String val) {
    return NoteAuthor.values.firstWhere(
      (e) => e.name == val.toUpperCase(),
      orElse: () => NoteAuthor.INVESTIGATOR,
    );
  }
}

class CaseNote {
  final String id;
  final String criminalId;
  final NoteAuthor author;
  final String text;
  final int createdAt;

  const CaseNote({
    required this.id,
    required this.criminalId,
    required this.author,
    required this.text,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'criminalId': criminalId,
      'author': author.name,
      'text': text,
      'createdAt': createdAt,
    };
  }

  factory CaseNote.fromMap(Map<String, dynamic> map) {
    return CaseNote(
      id: map['id'] as String,
      criminalId: map['criminalId'] as String,
      author: NoteAuthor.fromString(map['author'] as String? ?? 'INVESTIGATOR'),
      text: map['text'] as String,
      createdAt: (map['createdAt'] as num).toInt(),
    );
  }
}
