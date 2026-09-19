import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/utils/id_generator.dart';
import 'models/sync_models.dart';
import 'network_checker.dart';
import 'remote_sync_transport.dart';

/// Result of a synchronization cycle.
class SyncCycleResult {
  final int itemsPushed;
  final int itemsPulled;
  final bool success;
  final String? error;

  const SyncCycleResult({
    required this.itemsPushed,
    required this.itemsPulled,
    required this.success,
    this.error,
  });
}

/// Orchestrates offline-first synchronization with the central Neon database.
///
/// Responsibilities:
/// 1. Outbound push: drains local `pending_sync` queue into Neon via [transport].
/// 2. Inbound pull: retrieves other investigators' contributions since `lastServerTs`
///    and merges them into local SQLite.
/// 3. Offline resilience: zero blocking of local operations when offline; opportunistic
///    sync when network connectivity is detected.
/// 4. Honest reporting: [statusNotifier] accurately displays local vs synced state.
class SyncManager {
  final Database _db;
  final RemoteSyncTransport _transport;
  final NetworkAvailabilityChecker _networkChecker;
  final String _deviceId;
  final Future<void> Function()? onDataPulled;

  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  String? _lastError;
  int _pendingCount = 0;
  int _lastServerTs = 0;

  late final ValueNotifier<SyncStatus> statusNotifier;
  StreamSubscription<bool>? _networkSub;

  SyncManager({
    required Database db,
    required RemoteSyncTransport transport,
    required NetworkAvailabilityChecker networkChecker,
    required String deviceId,
    this.onDataPulled,
  })  : _db = db,
        _transport = transport,
        _networkChecker = networkChecker,
        _deviceId = deviceId {
    statusNotifier = ValueNotifier<SyncStatus>(_currentStatus());
  }

  String get deviceId => _deviceId;
  SyncStatus get status => statusNotifier.value;

  SyncStatus _currentStatus() {
    return SyncStatus(
      isConfigured: _transport.isConfigured,
      isOnline: _networkChecker.isOnline,
      isSyncing: _isSyncing,
      pendingCount: _pendingCount,
      lastSyncTime: _lastSyncTime,
      lastError: _lastError,
    );
  }

  void _updateStatus() {
    statusNotifier.value = _currentStatus();
  }

  /// Initializes local sync metadata, starts network listener, and triggers startup sync.
  Future<void> initialize() async {
    // Read last pull timestamp
    final metaRows = await _db.query(
      'sync_metadata',
      where: 'key = ?',
      whereArgs: ['lastPullServerTs'],
    );
    if (metaRows.isNotEmpty) {
      _lastServerTs = int.tryParse(metaRows.first['value'] as String) ?? 0;
    }

    final lastSyncRows = await _db.query(
      'sync_metadata',
      where: 'key = ?',
      whereArgs: ['lastSyncSuccessTs'],
    );
    if (lastSyncRows.isNotEmpty) {
      final ms = int.tryParse(lastSyncRows.first['value'] as String);
      if (ms != null) _lastSyncTime = DateTime.fromMillisecondsSinceEpoch(ms);
    }

    await _refreshPendingCount();

    _networkSub = _networkChecker.onConnectivityChanged.listen((online) {
      _updateStatus();
      if (online && _transport.isConfigured) {
        // Opportunistic sync on connection regain
        syncNow();
      }
    });

    _updateStatus();

    // Initial opportunistic sync attempt if configured
    if (_networkChecker.isOnline && _transport.isConfigured) {
      unawaited(syncNow());
    }
  }

  Future<void> _refreshPendingCount() async {
    if (!_db.isOpen) return;
    final rows = await _db.rawQuery(
      "SELECT COUNT(*) AS c FROM pending_sync WHERE status != 'SYNCED'",
    );
    _pendingCount = (rows.first['c'] as num?)?.toInt() ?? 0;
    _updateStatus();
  }

  /// Enqueues a local entity mutation or audit record into the pending sync queue.
  Future<void> enqueue({
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, dynamic> payload,
    int? timestamp,
  }) async {
    if (!_db.isOpen) return;
    final item = PendingSyncItem(
      id: IdGenerator.generate('SYNC'),
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payload: jsonEncode(payload),
      localTs: timestamp ?? DateTime.now().millisecondsSinceEpoch,
      status: 'PENDING',
    );

    await _db.insert('pending_sync', item.toMap());
    await _refreshPendingCount();

    // Opportunistically sync if online
    if (_networkChecker.isOnline && _transport.isConfigured && !_isSyncing) {
      unawaited(syncNow());
    }
  }

  /// Triggers an immediate bidirectional sync cycle.
  Future<SyncCycleResult> syncNow() async {
    if (_isSyncing) {
      return const SyncCycleResult(
        itemsPushed: 0,
        itemsPulled: 0,
        success: false,
        error: 'Sync already in progress',
      );
    }

    if (!_transport.isConfigured) {
      _updateStatus();
      return const SyncCycleResult(
        itemsPushed: 0,
        itemsPulled: 0,
        success: true,
      );
    }

    _isSyncing = true;
    _lastError = null;
    _updateStatus();

    var pushedCount = 0;
    var pulledCount = 0;

    try {
      // Ensure central tables exist
      await _transport.ensureSchema();

      // 1. Outbound push
      final pendingRows = await _db.query(
        'pending_sync',
        where: "status = 'PENDING' OR status = 'FAILED'",
        orderBy: 'localTs ASC',
        limit: 100,
      );

      if (pendingRows.isNotEmpty) {
        final items = pendingRows.map(PendingSyncItem.fromMap).toList();
        final serverTs = await _transport.pushBatch(
          deviceId: _deviceId,
          items: items,
        );

        // Remove synced items from the queue
        final ids = items.map((i) => i.id).toList();
        await _db.transaction((txn) async {
          for (final id in ids) {
            await txn.delete(
              'pending_sync',
              where: 'id = ?',
              whereArgs: [id],
            );
          }
        });

        pushedCount = items.length;
        if (serverTs > _lastServerTs) {
          _lastServerTs = serverTs;
          await _saveMetadata('lastPullServerTs', '$_lastServerTs');
        }
      }

      // 2. Inbound pull
      final pullResult = await _transport.pullSince(
        _lastServerTs,
        excludeDeviceId: _deviceId,
      );

      if (!pullResult.isEmpty) {
        await _db.transaction((txn) async {
          for (final criminal in pullResult.criminals) {
            await txn.insert(
              'criminals',
              criminal.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          for (final note in pullResult.caseNotes) {
            await txn.insert(
              'case_notes',
              note.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          for (final media in pullResult.mediaItems) {
            await txn.insert(
              'media_items',
              media.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          for (final text in pullResult.textRecords) {
            await txn.insert(
              'text_records',
              text.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        });

        pulledCount = pullResult.totalCount;
        if (pullResult.maxServerTs > _lastServerTs) {
          _lastServerTs = pullResult.maxServerTs;
          await _saveMetadata('lastPullServerTs', '$_lastServerTs');
        }

        // Notify app that new records were added so RAG / graph can update
        if (onDataPulled != null) {
          try {
            await onDataPulled!();
          } catch (e) {
            debugPrint('Error running onDataPulled: $e');
          }
        }
      }

      _lastSyncTime = DateTime.now();
      await _saveMetadata(
        'lastSyncSuccessTs',
        '${_lastSyncTime!.millisecondsSinceEpoch}',
      );

      await _refreshPendingCount();
      return SyncCycleResult(
        itemsPushed: pushedCount,
        itemsPulled: pulledCount,
        success: true,
      );
    } catch (e) {
      _lastError = e.toString();
      // Increment retry count for pending items
      await _db.rawUpdate('''
        UPDATE pending_sync 
        SET retryCount = retryCount + 1, status = 'FAILED', lastError = ?
        WHERE status = 'PENDING'
      ''', [e.toString()]);

      await _refreshPendingCount();
      return SyncCycleResult(
        itemsPushed: pushedCount,
        itemsPulled: pulledCount,
        success: false,
        error: e.toString(),
      );
    } finally {
      _isSyncing = false;
      _updateStatus();
    }
  }

  Future<void> _saveMetadata(String key, String value) async {
    await _db.insert(
      'sync_metadata',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  void dispose() {
    _networkSub?.cancel();
    statusNotifier.dispose();
  }
}
