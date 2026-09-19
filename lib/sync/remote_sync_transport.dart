import '../models/case_note.dart';
import '../models/criminal.dart';
import '../models/media_item.dart';
import '../models/text_record.dart';
import 'models/sync_models.dart';

/// Aggregated result of an inbound pull from the central store.
class RemoteSyncPullResult {
  final List<Criminal> criminals;
  final List<CaseNote> caseNotes;
  final List<MediaItem> mediaItems;
  final List<TextRecord> textRecords;
  final int maxServerTs;

  const RemoteSyncPullResult({
    this.criminals = const [],
    this.caseNotes = const [],
    this.mediaItems = const [],
    this.textRecords = const [],
    required this.maxServerTs,
  });

  bool get isEmpty =>
      criminals.isEmpty &&
      caseNotes.isEmpty &&
      mediaItems.isEmpty &&
      textRecords.isEmpty;

  int get totalCount =>
      criminals.length +
      caseNotes.length +
      mediaItems.length +
      textRecords.length;
}

/// Abstract contract for remote database synchronization.
///
/// Implemented by [NeonClient] for live Neon PostgreSQL instances,
/// and by test doubles for simulating concurrent devices and out-of-order arrivals.
abstract interface class RemoteSyncTransport {
  bool get isConfigured;

  Future<bool> testConnection();

  Future<void> ensureSchema();

  Future<int> pushBatch({
    required String deviceId,
    required List<PendingSyncItem> items,
  });

  Future<RemoteSyncPullResult> pullSince(int lastServerTs, {String? excludeDeviceId});

  Future<List<CanonicalAuditEntry>> fetchCanonicalLogs({int limit = 50});

  Future<bool> verifyCanonicalChain();
}
