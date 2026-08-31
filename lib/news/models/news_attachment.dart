enum NewsAttachedBy {
  INVESTIGATOR;

  String get displayName => 'Investigator';

  static NewsAttachedBy fromString(String val) {
    return NewsAttachedBy.values.firstWhere(
      (e) => e.name == val.toUpperCase(),
      orElse: () => NewsAttachedBy.INVESTIGATOR,
    );
  }
}

class NewsAttachment {
  final String id;
  final String criminalId;
  final String title;
  final String url;
  final String? imagePath;
  final NewsAttachedBy attachedBy;
  final int createdAt;

  const NewsAttachment({
    required this.id,
    required this.criminalId,
    required this.title,
    required this.url,
    this.imagePath,
    this.attachedBy = NewsAttachedBy.INVESTIGATOR,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'criminalId': criminalId,
      'title': title,
      'url': url,
      'imagePath': imagePath,
      'attachedBy': attachedBy.name,
      'createdAt': createdAt,
    };
  }

  factory NewsAttachment.fromMap(Map<String, dynamic> map) {
    return NewsAttachment(
      id: map['id'] as String,
      criminalId: map['criminalId'] as String,
      title: map['title'] as String,
      url: map['url'] as String,
      imagePath: map['imagePath'] as String?,
      attachedBy: NewsAttachedBy.fromString(map['attachedBy'] as String? ?? 'INVESTIGATOR'),
      createdAt: (map['createdAt'] as num).toInt(),
    );
  }
}
