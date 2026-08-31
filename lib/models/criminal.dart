import 'dart:convert';

enum CriminalStatus {
  AT_LARGE,
  IN_CUSTODY,
  UNDER_WATCH,
  DECEASED;

  String get displayName {
    switch (this) {
      case CriminalStatus.AT_LARGE:
        return 'At Large';
      case CriminalStatus.IN_CUSTODY:
        return 'In Custody';
      case CriminalStatus.UNDER_WATCH:
        return 'Under Watch';
      case CriminalStatus.DECEASED:
        return 'Deceased';
    }
  }

  static CriminalStatus fromString(String val) {
    return CriminalStatus.values.firstWhere(
      (e) => e.name == val.toUpperCase(),
      orElse: () => CriminalStatus.AT_LARGE,
    );
  }
}

enum RiskLevel {
  LOW,
  MED,
  HIGH;

  String get displayName {
    switch (this) {
      case RiskLevel.LOW:
        return 'Low Risk';
      case RiskLevel.MED:
        return 'Medium Risk';
      case RiskLevel.HIGH:
        return 'High Risk';
    }
  }

  static RiskLevel fromString(String val) {
    return RiskLevel.values.firstWhere(
      (e) => e.name == val.toUpperCase(),
      orElse: () => RiskLevel.MED,
    );
  }
}

class Criminal {
  final String id;
  final String name;
  final List<String> aliases;
  final String dob;
  final String gender;
  final String knownFor;
  final CriminalStatus status;
  final String lastKnownLoc;
  final RiskLevel riskLevel;
  final int createdAt;
  final int updatedAt;
  final bool isDeleted;

  const Criminal({
    required this.id,
    required this.name,
    required this.aliases,
    required this.dob,
    required this.gender,
    required this.knownFor,
    required this.status,
    required this.lastKnownLoc,
    required this.riskLevel,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  });

  Criminal copyWith({
    String? id,
    String? name,
    List<String>? aliases,
    String? dob,
    String? gender,
    String? knownFor,
    CriminalStatus? status,
    String? lastKnownLoc,
    RiskLevel? riskLevel,
    int? createdAt,
    int? updatedAt,
    bool? isDeleted,
  }) {
    return Criminal(
      id: id ?? this.id,
      name: name ?? this.name,
      aliases: aliases ?? this.aliases,
      dob: dob ?? this.dob,
      gender: gender ?? this.gender,
      knownFor: knownFor ?? this.knownFor,
      status: status ?? this.status,
      lastKnownLoc: lastKnownLoc ?? this.lastKnownLoc,
      riskLevel: riskLevel ?? this.riskLevel,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'aliases': jsonEncode(aliases),
      'dob': dob,
      'gender': gender,
      'knownFor': knownFor,
      'status': status.name,
      'lastKnownLoc': lastKnownLoc,
      'riskLevel': riskLevel.name,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'isDeleted': isDeleted ? 1 : 0,
    };
  }

  factory Criminal.fromMap(Map<String, dynamic> map) {
    List<String> parsedAliases = [];
    if (map['aliases'] != null) {
      if (map['aliases'] is String) {
        try {
          final decoded = jsonDecode(map['aliases'] as String);
          if (decoded is List) {
            parsedAliases = decoded.map((e) => e.toString()).toList();
          }
        } catch (_) {
          parsedAliases = [];
        }
      } else if (map['aliases'] is List) {
        parsedAliases = (map['aliases'] as List).map((e) => e.toString()).toList();
      }
    }

    return Criminal(
      id: map['id'] as String,
      name: map['name'] as String,
      aliases: parsedAliases,
      dob: map['dob'] as String? ?? '',
      gender: map['gender'] as String? ?? '',
      knownFor: map['knownFor'] as String? ?? '',
      status: CriminalStatus.fromString(map['status'] as String? ?? 'AT_LARGE'),
      lastKnownLoc: map['lastKnownLoc'] as String? ?? '',
      riskLevel: RiskLevel.fromString(map['riskLevel'] as String? ?? 'MED'),
      createdAt: (map['createdAt'] as num).toInt(),
      updatedAt: (map['updatedAt'] as num).toInt(),
      isDeleted: (map['isDeleted'] as num? ?? 0) == 1,
    );
  }
}
