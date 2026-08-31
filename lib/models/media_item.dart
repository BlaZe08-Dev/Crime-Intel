enum MediaType {
  MUGSHOT,
  PHOTO,
  CRIME_SCENE,
  DOCUMENT,
  ENHANCED;

  String get displayName {
    switch (this) {
      case MediaType.MUGSHOT:
        return 'Mugshot';
      case MediaType.PHOTO:
        return 'Photo';
      case MediaType.CRIME_SCENE:
        return 'Crime Scene';
      case MediaType.DOCUMENT:
        return 'Document';
      case MediaType.ENHANCED:
        return 'Enhanced Image';
    }
  }

  static MediaType fromString(String val) {
    return MediaType.values.firstWhere(
      (e) => e.name == val.toUpperCase(),
      orElse: () => MediaType.PHOTO,
    );
  }
}

class MediaItem {
  final String id;
  final String? criminalId;
  final MediaType type;
  final String filePath;
  final String caption;
  final String? sourceItemId;
  final bool isSynthetic;
  final int createdAt;

  const MediaItem({
    required this.id,
    this.criminalId,
    required this.type,
    required this.filePath,
    required this.caption,
    this.sourceItemId,
    this.isSynthetic = true,
    required this.createdAt,
  });

  MediaItem copyWith({
    String? id,
    String? criminalId,
    MediaType? type,
    String? filePath,
    String? caption,
    String? sourceItemId,
    bool? isSynthetic,
    int? createdAt,
  }) {
    return MediaItem(
      id: id ?? this.id,
      criminalId: criminalId ?? this.criminalId,
      type: type ?? this.type,
      filePath: filePath ?? this.filePath,
      caption: caption ?? this.caption,
      sourceItemId: sourceItemId ?? this.sourceItemId,
      isSynthetic: isSynthetic ?? this.isSynthetic,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'criminalId': criminalId,
      'type': type.name,
      'filePath': filePath,
      'caption': caption,
      'sourceItemId': sourceItemId,
      'isSynthetic': isSynthetic ? 1 : 0,
      'createdAt': createdAt,
    };
  }

  factory MediaItem.fromMap(Map<String, dynamic> map) {
    return MediaItem(
      id: map['id'] as String,
      criminalId: map['criminalId'] as String?,
      type: MediaType.fromString(map['type'] as String? ?? 'PHOTO'),
      filePath: map['filePath'] as String,
      caption: map['caption'] as String? ?? '',
      sourceItemId: map['sourceItemId'] as String?,
      isSynthetic: (map['isSynthetic'] as num? ?? 1) == 1,
      createdAt: (map['createdAt'] as num).toInt(),
    );
  }
}
