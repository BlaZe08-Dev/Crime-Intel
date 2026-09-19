import '../../audit/models/log_entry.dart';
import '../../core/utils/crypto_utils.dart';

/// Represents a local mutation or audit record waiting to be synced to Neon.
class PendingSyncItem {
  final String id;
  final String entityType;
  final String entityId;
  final String operation;
  final String payload;
  final int localTs;
  final String status;
  final int retryCount;
  final String? lastError;

  const PendingSyncItem({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.localTs,
    this.status = 'PENDING',
    this.retryCount = 0,
    this.lastError,
  });

  PendingSyncItem copyWith({
    String? status,
    int? retryCount,
    String? lastError,
  }) {
    return PendingSyncItem(
      id: id,
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payload: payload,
      localTs: localTs,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'entityType': entityType,
      'entityId': entityId,
      'operation': operation,
      'payload': payload,
      'localTs': localTs,
      'status': status,
      'retryCount': retryCount,
      'lastError': lastError,
    };
  }

  factory PendingSyncItem.fromMap(Map<String, dynamic> map) {
    return PendingSyncItem(
      id: map['id'] as String,
      entityType: map['entityType'] as String,
      entityId: map['entityId'] as String,
      operation: map['operation'] as String,
      payload: map['payload'] as String,
      localTs: (map['localTs'] as num).toInt(),
      status: map['status'] as String? ?? 'PENDING',
      retryCount: (map['retryCount'] as num?)?.toInt() ?? 0,
      lastError: map['lastError'] as String?,
    );
  }
}

/// State of network connectivity and central database sync.
class SyncStatus {
  final bool isConfigured;
  final bool isOnline;
  final bool isSyncing;
  final int pendingCount;
  final DateTime? lastSyncTime;
  final String? lastError;

  const SyncStatus({
    required this.isConfigured,
    required this.isOnline,
    required this.isSyncing,
    required this.pendingCount,
    this.lastSyncTime,
    this.lastError,
  });

  SyncStatus copyWith({
    bool? isConfigured,
    bool? isOnline,
    bool? isSyncing,
    int? pendingCount,
    DateTime? lastSyncTime,
    String? lastError,
  }) {
    return SyncStatus(
      isConfigured: isConfigured ?? this.isConfigured,
      isOnline: isOnline ?? this.isOnline,
      isSyncing: isSyncing ?? this.isSyncing,
      pendingCount: pendingCount ?? this.pendingCount,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      lastError: lastError ?? this.lastError,
    );
  }

  /// User-facing descriptive summary for UI indicators.
  String get label {
    if (!isConfigured) return 'Local Only (Neon unconfigured)';
    if (isSyncing) return 'Syncing with Neon...';
    if (!isOnline) {
      if (pendingCount > 0) {
        return 'Offline — saved locally, will sync later';
      }
      if (lastSyncTime != null) {
        return 'Offline — Last synced ${_formatRelativeTime(lastSyncTime!)}';
      }
      return 'Offline — saved locally, will sync later';
    }
    if (pendingCount > 0) {
      return pendingCount == 1
          ? '1 item pending sync'
          : '$pendingCount items pending sync';
    }
    if (lastSyncTime != null) {
      return 'Last synced ${_formatRelativeTime(lastSyncTime!)}';
    }
    return 'Awaiting initial sync';
  }

  static String _formatRelativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${time.month}/${time.day} ${time.hour}:${time.minute.toString().padLeft(2, '0')}';
  }
}

/// Entry in the central canonical audit log stored on Neon.
///
/// **Two-chain design invariant:**
/// Neon assigns the sequence (`seq`) and hash in strict server arrival order,
/// recording both the original device timestamp (`localTs`) and server arrival
/// timestamp (`serverTs`).
class CanonicalAuditEntry {
  final int seq;
  final String deviceId;
  final int localSeq;
  final LogActor actor;
  final LogAction action;
  final String targetType;
  final String targetId;
  final String payloadHash;
  final int localTs;
  final int serverTs;
  final String prevHash;
  final String entryHash;
  final String? payloadJson;

  const CanonicalAuditEntry({
    required this.seq,
    required this.deviceId,
    required this.localSeq,
    required this.actor,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.payloadHash,
    required this.localTs,
    required this.serverTs,
    required this.prevHash,
    required this.entryHash,
    this.payloadJson,
  });

  /// Hash formula for the central canonical chain:
  /// SHA256(seq|deviceId|actor|action|targetType|targetId|payloadHash|localTs|serverTs|prevHash)
  static String computeEntryHash({
    required int seq,
    required String deviceId,
    required LogActor actor,
    required LogAction action,
    required String targetType,
    required String targetId,
    required String payloadHash,
    required int localTs,
    required int serverTs,
    required String prevHash,
  }) {
    final raw = '$seq|$deviceId|${actor.name}|${action.name}|$targetType|'
        '$targetId|$payloadHash|$localTs|$serverTs|$prevHash';
    return CryptoUtils.sha256Hash(raw);
  }

  Map<String, dynamic> toMap() {
    return {
      'seq': seq,
      'deviceId': deviceId,
      'localSeq': localSeq,
      'actor': actor.name,
      'action': action.name,
      'targetType': targetType,
      'targetId': targetId,
      'payloadHash': payloadHash,
      'localTs': localTs,
      'serverTs': serverTs,
      'prevHash': prevHash,
      'entryHash': entryHash,
      'payloadJson': payloadJson,
    };
  }

  factory CanonicalAuditEntry.fromMap(Map<String, dynamic> map) {
    return CanonicalAuditEntry(
      seq: (map['seq'] as num).toInt(),
      deviceId: map['deviceId'] as String? ?? 'UNKNOWN_DEVICE',
      localSeq: (map['localSeq'] as num?)?.toInt() ?? 0,
      actor: LogActor.fromString(map['actor'] as String? ?? 'SYSTEM'),
      action: LogAction.fromString(map['action'] as String? ?? 'VIEW_RECORD'),
      targetType: map['targetType'] as String,
      targetId: map['targetId'] as String,
      payloadHash: map['payloadHash'] as String,
      localTs: (map['localTs'] as num).toInt(),
      serverTs: (map['serverTs'] as num).toInt(),
      prevHash: map['prevHash'] as String,
      entryHash: map['entryHash'] as String,
      payloadJson: map['payloadJson'] as String?,
    );
  }
}
