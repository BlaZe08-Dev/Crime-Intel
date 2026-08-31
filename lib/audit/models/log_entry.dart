enum LogActor {
  INVESTIGATOR,
  ASSISTANT,
  SYSTEM;

  String get displayName {
    switch (this) {
      case LogActor.INVESTIGATOR:
        return 'Investigator';
      case LogActor.ASSISTANT:
        return 'AI Assistant';
      case LogActor.SYSTEM:
        return 'System Engine';
    }
  }

  static LogActor fromString(String val) {
    return LogActor.values.firstWhere(
      (e) => e.name == val.toUpperCase(),
      orElse: () => LogActor.SYSTEM,
    );
  }
}

enum LogAction {
  LOGIN_OK,
  LOGIN_FAIL,
  OTP_SENT,
  OTP_OK,
  VIEW_RECORD,
  UPLOAD,
  UPDATE,
  DELETE,
  CREATE_CASENOTE,
  ENHANCE_IMAGE,
  ATTACH_NEWS,
  LLM_QUERY;

  String get displayName {
    switch (this) {
      case LogAction.LOGIN_OK:
        return 'Login Successful';
      case LogAction.LOGIN_FAIL:
        return 'Login Failed';
      case LogAction.OTP_SENT:
        return 'OTP Dispatched';
      case LogAction.OTP_OK:
        return 'OTP Verified';
      case LogAction.VIEW_RECORD:
        return 'Record Viewed';
      case LogAction.UPLOAD:
        return 'Data Uploaded';
      case LogAction.UPDATE:
        return 'Data Updated';
      case LogAction.DELETE:
        return 'Data Soft-Deleted';
      case LogAction.CREATE_CASENOTE:
        return 'Case Note Created';
      case LogAction.ENHANCE_IMAGE:
        return 'Image Enhanced';
      case LogAction.ATTACH_NEWS:
        return 'News Attached';
      case LogAction.LLM_QUERY:
        return 'Assistant Query Executed';
    }
  }

  static LogAction fromString(String val) {
    return LogAction.values.firstWhere(
      (e) => e.name == val.toUpperCase(),
      orElse: () => LogAction.VIEW_RECORD,
    );
  }
}

class LogEntry {
  final int seq;
  final LogActor actor;
  final LogAction action;
  final String targetType;
  final String targetId;
  final String payloadHash;
  final int ts;
  final String prevHash;
  final String entryHash;

  const LogEntry({
    required this.seq,
    required this.actor,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.payloadHash,
    required this.ts,
    required this.prevHash,
    required this.entryHash,
  });

  Map<String, dynamic> toMap() {
    return {
      'seq': seq,
      'actor': actor.name,
      'action': action.name,
      'targetType': targetType,
      'targetId': targetId,
      'payloadHash': payloadHash,
      'ts': ts,
      'prevHash': prevHash,
      'entryHash': entryHash,
    };
  }

  factory LogEntry.fromMap(Map<String, dynamic> map) {
    return LogEntry(
      seq: (map['seq'] as num).toInt(),
      actor: LogActor.fromString(map['actor'] as String? ?? 'SYSTEM'),
      action: LogAction.fromString(map['action'] as String? ?? 'VIEW_RECORD'),
      targetType: map['targetType'] as String? ?? '',
      targetId: map['targetId'] as String? ?? '',
      payloadHash: map['payloadHash'] as String? ?? '',
      ts: (map['ts'] as num).toInt(),
      prevHash: map['prevHash'] as String? ?? '',
      entryHash: map['entryHash'] as String? ?? '',
    );
  }
}
