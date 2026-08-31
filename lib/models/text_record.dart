enum TextRecordKind {
  FIR,
  INTEL,
  SURVEILLANCE_NOTE,
  REPORT;

  String get displayName {
    switch (this) {
      case TextRecordKind.FIR:
        return 'FIR';
      case TextRecordKind.INTEL:
        return 'Intelligence Report';
      case TextRecordKind.SURVEILLANCE_NOTE:
        return 'Surveillance Note';
      case TextRecordKind.REPORT:
        return 'Case Report';
    }
  }

  static TextRecordKind fromString(String val) {
    return TextRecordKind.values.firstWhere(
      (e) => e.name == val.toUpperCase(),
      orElse: () => TextRecordKind.INTEL,
    );
  }
}

class TextRecord {
  final String id;
  final String? criminalId;
  final TextRecordKind kind;
  final String title;
  final String body;
  final int createdAt;

  const TextRecord({
    required this.id,
    this.criminalId,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'criminalId': criminalId,
      'kind': kind.name,
      'title': title,
      'body': body,
      'createdAt': createdAt,
    };
  }

  factory TextRecord.fromMap(Map<String, dynamic> map) {
    return TextRecord(
      id: map['id'] as String,
      criminalId: map['criminalId'] as String?,
      kind: TextRecordKind.fromString(map['kind'] as String? ?? 'INTEL'),
      title: map['title'] as String,
      body: map['body'] as String,
      createdAt: (map['createdAt'] as num).toInt(),
    );
  }
}
