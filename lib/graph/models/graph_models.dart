import 'dart:convert';

enum EntityType {
  PERSON,
  LOCATION,
  VEHICLE,
  PHONE,
  ORG;

  String get displayName {
    switch (this) {
      case EntityType.PERSON:
        return 'Person';
      case EntityType.LOCATION:
        return 'Location';
      case EntityType.VEHICLE:
        return 'Vehicle';
      case EntityType.PHONE:
        return 'Phone';
      case EntityType.ORG:
        return 'Organization';
    }
  }

  static EntityType fromString(String val) {
    return EntityType.values.firstWhere(
      (e) => e.name == val.toUpperCase(),
      orElse: () => EntityType.PERSON,
    );
  }
}

enum RelationType {
  CALLED,
  PAID,
  CO_OCCURRED,
  ASSOCIATED,
  LOCATED_AT;

  String get displayName {
    switch (this) {
      case RelationType.CALLED:
        return 'Called';
      case RelationType.PAID:
        return 'Paid';
      case RelationType.CO_OCCURRED:
        return 'Co-occurred with';
      case RelationType.ASSOCIATED:
        return 'Associated with';
      case RelationType.LOCATED_AT:
        return 'Located at';
    }
  }

  static RelationType fromString(String val) {
    return RelationType.values.firstWhere(
      (e) => e.name == val.toUpperCase(),
      orElse: () => RelationType.ASSOCIATED,
    );
  }
}

class Entity {
  final String id;
  final EntityType type;
  final String value;
  final String firstSeenIn;

  const Entity({
    required this.id,
    required this.type,
    required this.value,
    required this.firstSeenIn,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.name,
      'value': value,
      'firstSeenIn': firstSeenIn,
    };
  }

  factory Entity.fromMap(Map<String, dynamic> map) {
    return Entity(
      id: map['id'] as String,
      type: EntityType.fromString(map['type'] as String? ?? 'PERSON'),
      value: map['value'] as String,
      firstSeenIn: map['firstSeenIn'] as String? ?? '',
    );
  }
}

class Edge {
  final String id;
  final String srcEntityId;
  final String dstEntityId;
  final RelationType relation;
  final int weight;
  final List<String> evidenceIds;

  const Edge({
    required this.id,
    required this.srcEntityId,
    required this.dstEntityId,
    required this.relation,
    this.weight = 1,
    this.evidenceIds = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'srcEntityId': srcEntityId,
      'dstEntityId': dstEntityId,
      'relation': relation.name,
      'weight': weight,
      'evidenceIds': jsonEncode(evidenceIds),
    };
  }

  factory Edge.fromMap(Map<String, dynamic> map) {
    List<String> parsedEvidence = [];
    if (map['evidenceIds'] != null) {
      if (map['evidenceIds'] is String) {
        try {
          final decoded = jsonDecode(map['evidenceIds'] as String);
          if (decoded is List) {
            parsedEvidence = decoded.map((e) => e.toString()).toList();
          }
        } catch (_) {
          parsedEvidence = [];
        }
      } else if (map['evidenceIds'] is List) {
        parsedEvidence = (map['evidenceIds'] as List).map((e) => e.toString()).toList();
      }
    }

    return Edge(
      id: map['id'] as String,
      srcEntityId: map['srcEntityId'] as String,
      dstEntityId: map['dstEntityId'] as String,
      relation: RelationType.fromString(map['relation'] as String? ?? 'ASSOCIATED'),
      weight: (map['weight'] as num? ?? 1).toInt(),
      evidenceIds: parsedEvidence,
    );
  }
}
