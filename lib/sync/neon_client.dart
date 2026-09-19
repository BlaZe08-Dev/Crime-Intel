import 'dart:convert';
import 'package:postgres/postgres.dart';

import '../audit/models/log_entry.dart';
import '../core/constants/constants.dart';
import '../core/errors/app_exceptions.dart';
import '../models/case_note.dart';
import '../models/criminal.dart';
import '../models/media_item.dart';
import '../models/text_record.dart';
import 'models/sync_models.dart';
import 'remote_sync_transport.dart';

/// PostgreSQL client for Neon integration.
///
/// Implements [RemoteSyncTransport] to maintain the central canonical database:
/// - Shared domain entities (`shared_criminals`, `shared_case_notes`, etc.)
/// - The canonical audit log (`central_audit_log`) where entries are sequenced
///   strictly in server arrival order, never by local device creation time.
class NeonClient implements RemoteSyncTransport {
  final String connectionUrl;

  NeonClient({required this.connectionUrl});

  @override
  bool get isConfigured => connectionUrl.trim().isNotEmpty;

  Endpoint? _parseEndpoint() {
    if (!isConfigured) return null;
    try {
      final uri = Uri.parse(connectionUrl.trim());
      final userInfo = uri.userInfo;
      String? username;
      String? password;
      if (userInfo.isNotEmpty) {
        final parts = userInfo.split(':');
        username = parts[0];
        if (parts.length > 1) password = parts.sublist(1).join(':');
      }

      final dbName = uri.pathSegments.isNotEmpty && uri.pathSegments.first.isNotEmpty
          ? uri.pathSegments.first
          : 'neondb';

      return Endpoint(
        host: uri.host,
        port: uri.port == 0 ? 5432 : uri.port,
        database: dbName,
        username: username,
        password: password,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Connection> _openConnection() async {
    final endpoint = _parseEndpoint();
    if (endpoint == null) {
      throw const DataAccessException('Neon connection URL is invalid or unset.');
    }

    const settings = ConnectionSettings(
      sslMode: SslMode.require,
      connectTimeout: Duration(seconds: 30),
      queryTimeout: Duration(seconds: 45),
    );

    try {
      return await Connection.open(endpoint, settings: settings);
    } catch (e) {
      // Retry once after a brief pause in case serverless compute is waking up
      try {
        await Future<void>.delayed(const Duration(milliseconds: 750));
        return await Connection.open(endpoint, settings: settings);
      } catch (retryError) {
        throw DataAccessException(
            'Could not connect to Neon database: $retryError',
            cause: retryError);
      }
    }
  }

  @override
  Future<bool> testConnection() async {
    if (!isConfigured) return false;
    Connection? conn;
    try {
      conn = await _openConnection();
      final res = await conn.execute('SELECT 1');
      return res.isNotEmpty;
    } catch (_) {
      return false;
    } finally {
      await conn?.close();
    }
  }

  @override
  Future<void> ensureSchema() async {
    if (!isConfigured) return;
    Connection? conn;
    try {
      final connection = await _openConnection();
      conn = connection;
      final statements = [
        '''
        CREATE TABLE IF NOT EXISTS shared_criminals (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          aliases TEXT NOT NULL,
          dob TEXT NOT NULL,
          gender TEXT NOT NULL,
          known_for TEXT NOT NULL,
          status TEXT NOT NULL,
          last_known_loc TEXT NOT NULL,
          risk_level TEXT NOT NULL,
          created_at BIGINT NOT NULL,
          updated_at BIGINT NOT NULL,
          is_deleted INT NOT NULL DEFAULT 0,
          synced_at BIGINT NOT NULL,
          source_device_id TEXT
        )
        ''',
        'CREATE INDEX IF NOT EXISTS idx_shared_criminals_synced ON shared_criminals (synced_at)',
        '''
        CREATE TABLE IF NOT EXISTS shared_case_notes (
          id TEXT PRIMARY KEY,
          criminal_id TEXT NOT NULL,
          author TEXT NOT NULL,
          text TEXT NOT NULL,
          created_at BIGINT NOT NULL,
          synced_at BIGINT NOT NULL,
          source_device_id TEXT
        )
        ''',
        'CREATE INDEX IF NOT EXISTS idx_shared_case_notes_synced ON shared_case_notes (synced_at)',
        '''
        CREATE TABLE IF NOT EXISTS shared_media_items (
          id TEXT PRIMARY KEY,
          criminal_id TEXT,
          type TEXT NOT NULL,
          file_path TEXT NOT NULL,
          caption TEXT NOT NULL,
          source_item_id TEXT,
          is_synthetic INT NOT NULL DEFAULT 1,
          created_at BIGINT NOT NULL,
          synced_at BIGINT NOT NULL,
          source_device_id TEXT,
          uploaded_by_investigator_id TEXT NOT NULL DEFAULT 'system',
          deleted_at BIGINT
        )
        ''',
        'ALTER TABLE shared_media_items ADD COLUMN IF NOT EXISTS uploaded_by_investigator_id TEXT NOT NULL DEFAULT \'system\'',
        'ALTER TABLE shared_media_items ADD COLUMN IF NOT EXISTS deleted_at BIGINT',
        'CREATE INDEX IF NOT EXISTS idx_shared_media_items_synced ON shared_media_items (synced_at)',
        '''
        CREATE TABLE IF NOT EXISTS shared_text_records (
          id TEXT PRIMARY KEY,
          criminal_id TEXT,
          kind TEXT NOT NULL,
          title TEXT NOT NULL,
          body TEXT NOT NULL,
          created_at BIGINT NOT NULL,
          synced_at BIGINT NOT NULL,
          source_device_id TEXT
        )
        ''',
        'CREATE INDEX IF NOT EXISTS idx_shared_text_records_synced ON shared_text_records (synced_at)',
        '''
        CREATE TABLE IF NOT EXISTS central_audit_log (
          seq BIGSERIAL PRIMARY KEY,
          device_id TEXT NOT NULL,
          local_seq INT NOT NULL,
          actor TEXT NOT NULL,
          action TEXT NOT NULL,
          target_type TEXT NOT NULL,
          target_id TEXT NOT NULL,
          payload_hash TEXT NOT NULL,
          local_ts BIGINT NOT NULL,
          server_ts BIGINT NOT NULL,
          prev_hash TEXT NOT NULL,
          entry_hash TEXT NOT NULL,
          payload_json TEXT
        )
        ''',
        'CREATE INDEX IF NOT EXISTS idx_central_audit_server_ts ON central_audit_log (server_ts)',
        'CREATE INDEX IF NOT EXISTS idx_central_audit_device ON central_audit_log (device_id)',
      ];

      for (final stmt in statements) {
        await connection.execute(stmt);
      }
    } finally {
      await conn?.close();
    }
  }

  @override
  Future<int> pushBatch({
    required String deviceId,
    required List<PendingSyncItem> items,
  }) async {
    if (!isConfigured || items.isEmpty) {
      return DateTime.now().millisecondsSinceEpoch;
    }

    Connection? conn;
    try {
      conn = await _openConnection();
      final serverTs = DateTime.now().millisecondsSinceEpoch;

      await conn.runTx((ctx) async {
        for (final item in items) {
          final data = jsonDecode(item.payload) as Map<String, dynamic>;

          if (item.entityType == 'criminal') {
            await ctx.execute(
              Sql.named('''
                INSERT INTO shared_criminals (
                  id, name, aliases, dob, gender, known_for, status,
                  last_known_loc, risk_level, created_at, updated_at,
                  is_deleted, synced_at, source_device_id
                ) VALUES (
                  @id, @name, @aliases, @dob, @gender, @knownFor, @status,
                  @lastKnownLoc, @riskLevel, @createdAt, @updatedAt,
                  @isDeleted, @syncedAt, @sourceDeviceId
                )
                ON CONFLICT (id) DO UPDATE SET
                  name = EXCLUDED.name,
                  aliases = EXCLUDED.aliases,
                  dob = EXCLUDED.dob,
                  gender = EXCLUDED.gender,
                  known_for = EXCLUDED.known_for,
                  status = EXCLUDED.status,
                  last_known_loc = EXCLUDED.last_known_loc,
                  risk_level = EXCLUDED.risk_level,
                  updated_at = EXCLUDED.updated_at,
                  is_deleted = EXCLUDED.is_deleted,
                  synced_at = EXCLUDED.synced_at,
                  source_device_id = EXCLUDED.source_device_id
              '''),
              parameters: {
                'id': data['id'],
                'name': data['name'],
                'aliases': data['aliases'] is List ? (data['aliases'] as List).join(',') : data['aliases'],
                'dob': data['dob'],
                'gender': data['gender'],
                'knownFor': data['knownFor'],
                'status': data['status'],
                'lastKnownLoc': data['lastKnownLoc'],
                'riskLevel': data['riskLevel'],
                'createdAt': data['createdAt'],
                'updatedAt': data['updatedAt'] ?? data['createdAt'],
                'isDeleted': data['isDeleted'] ?? 0,
                'syncedAt': serverTs,
                'sourceDeviceId': deviceId,
              },
            );
          } else if (item.entityType == 'case_note') {
            await ctx.execute(
              Sql.named('''
                INSERT INTO shared_case_notes (
                  id, criminal_id, author, text, created_at, synced_at, source_device_id
                ) VALUES (
                  @id, @criminalId, @author, @text, @createdAt, @syncedAt, @sourceDeviceId
                )
                ON CONFLICT (id) DO UPDATE SET
                  author = EXCLUDED.author,
                  text = EXCLUDED.text,
                  synced_at = EXCLUDED.synced_at,
                  source_device_id = EXCLUDED.source_device_id
              '''),
              parameters: {
                'id': data['id'],
                'criminalId': data['criminalId'],
                'author': data['author'],
                'text': data['text'],
                'createdAt': data['createdAt'],
                'syncedAt': serverTs,
                'sourceDeviceId': deviceId,
              },
            );
          } else if (item.entityType == 'media_item') {
            await ctx.execute(
              Sql.named('''
                INSERT INTO shared_media_items (
                  id, criminal_id, type, file_path, caption, source_item_id,
                  is_synthetic, created_at, synced_at, source_device_id,
                  uploaded_by_investigator_id, deleted_at
                ) VALUES (
                  @id, @criminalId, @type, @filePath, @caption, @sourceItemId,
                  @isSynthetic, @createdAt, @syncedAt, @sourceDeviceId,
                  @uploadedByInvestigatorId, @deletedAt
                )
                ON CONFLICT (id) DO UPDATE SET
                  caption = EXCLUDED.caption,
                  deleted_at = EXCLUDED.deleted_at,
                  synced_at = EXCLUDED.synced_at,
                  source_device_id = EXCLUDED.source_device_id
              '''),
              parameters: {
                'id': data['id'],
                'criminalId': data['criminalId'],
                'type': data['type'],
                'filePath': data['filePath'],
                'caption': data['caption'],
                'sourceItemId': data['sourceItemId'],
                'isSynthetic': data['isSynthetic'] ?? 1,
                'createdAt': data['createdAt'],
                'syncedAt': serverTs,
                'sourceDeviceId': deviceId,
                'uploadedByInvestigatorId':
                    data['uploadedByInvestigatorId'] ?? 'system',
                'deletedAt': data['deletedAt'],
              },
            );
          } else if (item.entityType == 'text_record') {
            await ctx.execute(
              Sql.named('''
                INSERT INTO shared_text_records (
                  id, criminal_id, kind, title, body, created_at, synced_at, source_device_id
                ) VALUES (
                  @id, @criminalId, @kind, @title, @body, @createdAt, @syncedAt, @sourceDeviceId
                )
                ON CONFLICT (id) DO UPDATE SET
                  title = EXCLUDED.title,
                  body = EXCLUDED.body,
                  synced_at = EXCLUDED.synced_at,
                  source_device_id = EXCLUDED.source_device_id
              '''),
              parameters: {
                'id': data['id'],
                'criminalId': data['criminalId'],
                'kind': data['kind'],
                'title': data['title'],
                'body': data['body'],
                'createdAt': data['createdAt'],
                'syncedAt': serverTs,
                'sourceDeviceId': deviceId,
              },
            );
          } else if (item.entityType == 'audit_entry') {
            // Append to canonical central chain
            final latestRes = await ctx.execute(
              'SELECT seq, entry_hash FROM central_audit_log ORDER BY seq DESC LIMIT 1',
            );

            var nextSeq = 1;
            var prevHash = AppConstants.genesisHash;
            if (latestRes.isNotEmpty) {
              nextSeq = (latestRes.first[0] as num).toInt() + 1;
              prevHash = latestRes.first[1] as String;
            }

            final actor = LogActor.fromString(data['actor'] as String? ?? 'SYSTEM');
            final action = LogAction.fromString(data['action'] as String? ?? 'VIEW_RECORD');
            final targetType = data['targetType'] as String;
            final targetId = data['targetId'] as String;
            final payloadHash = data['payloadHash'] as String;
            final localSeq = (data['seq'] as num?)?.toInt() ?? 0;

            final entryHash = CanonicalAuditEntry.computeEntryHash(
              seq: nextSeq,
              deviceId: deviceId,
              actor: actor,
              action: action,
              targetType: targetType,
              targetId: targetId,
              payloadHash: payloadHash,
              localTs: item.localTs,
              serverTs: serverTs,
              prevHash: prevHash,
            );

            await ctx.execute(
              Sql.named('''
                INSERT INTO central_audit_log (
                  seq, device_id, local_seq, actor, action, target_type, target_id,
                  payload_hash, local_ts, server_ts, prev_hash, entry_hash, payload_json
                ) VALUES (
                  @seq, @deviceId, @localSeq, @actor, @action, @targetType, @targetId,
                  @payloadHash, @localTs, @serverTs, @prevHash, @entryHash, @payloadJson
                )
              '''),
              parameters: {
                'seq': nextSeq,
                'deviceId': deviceId,
                'localSeq': localSeq,
                'actor': actor.name,
                'action': action.name,
                'targetType': targetType,
                'targetId': targetId,
                'payloadHash': payloadHash,
                'localTs': item.localTs,
                'serverTs': serverTs,
                'prevHash': prevHash,
                'entryHash': entryHash,
                'payloadJson': item.payload,
              },
            );
          }
        }
      });

      return serverTs;
    } finally {
      await conn?.close();
    }
  }

  @override
  Future<RemoteSyncPullResult> pullSince(
    int lastServerTs, {
    String? excludeDeviceId,
  }) async {
    if (!isConfigured) {
      return RemoteSyncPullResult(maxServerTs: lastServerTs);
    }

    Connection? conn;
    try {
      conn = await _openConnection();
      var maxTs = lastServerTs;

      // Pull criminals
      final crimRes = await conn.execute(
        Sql.named('''
          SELECT id, name, aliases, dob, gender, known_for, status,
                 last_known_loc, risk_level, created_at, updated_at,
                 is_deleted, synced_at
          FROM shared_criminals
          WHERE synced_at > @lastTs
          ORDER BY synced_at ASC
        '''),
        parameters: {'lastTs': lastServerTs},
      );

      final criminals = <Criminal>[];
      for (final r in crimRes) {
        final row = r.toColumnMap();
        final aliasesRaw = row['aliases'] as String? ?? '';
        final aliases = aliasesRaw.isEmpty ? <String>[] : aliasesRaw.split(',');
        final syncedAt = (row['synced_at'] as num).toInt();
        if (syncedAt > maxTs) maxTs = syncedAt;

        criminals.add(Criminal(
          id: row['id'] as String,
          name: row['name'] as String,
          aliases: aliases,
          dob: row['dob'] as String,
          gender: row['gender'] as String,
          knownFor: row['known_for'] as String,
          status: CriminalStatus.fromString(row['status'] as String),
          lastKnownLoc: row['last_known_loc'] as String,
          riskLevel: RiskLevel.fromString(row['risk_level'] as String),
          createdAt: (row['created_at'] as num).toInt(),
          updatedAt: (row['updated_at'] as num).toInt(),
          isDeleted: (row['is_deleted'] as num).toInt() == 1,
        ));
      }

      // Pull case notes
      final noteRes = await conn.execute(
        Sql.named('''
          SELECT id, criminal_id, author, text, created_at, synced_at
          FROM shared_case_notes
          WHERE synced_at > @lastTs
          ORDER BY synced_at ASC
        '''),
        parameters: {'lastTs': lastServerTs},
      );

      final caseNotes = <CaseNote>[];
      for (final r in noteRes) {
        final row = r.toColumnMap();
        final syncedAt = (row['synced_at'] as num).toInt();
        if (syncedAt > maxTs) maxTs = syncedAt;

        caseNotes.add(CaseNote(
          id: row['id'] as String,
          criminalId: row['criminal_id'] as String,
          author: NoteAuthor.fromString(row['author'] as String),
          text: row['text'] as String,
          createdAt: (row['created_at'] as num).toInt(),
        ));
      }

      // Pull media items
      final mediaRes = await conn.execute(
        Sql.named('''
          SELECT id, criminal_id, type, file_path, caption, source_item_id,
                 is_synthetic, created_at, synced_at,
                 uploaded_by_investigator_id, deleted_at
          FROM shared_media_items
          WHERE synced_at > @lastTs
          ORDER BY synced_at ASC
        '''),
        parameters: {'lastTs': lastServerTs},
      );

      final mediaItems = <MediaItem>[];
      for (final r in mediaRes) {
        final row = r.toColumnMap();
        final syncedAt = (row['synced_at'] as num).toInt();
        if (syncedAt > maxTs) maxTs = syncedAt;

        mediaItems.add(MediaItem(
          id: row['id'] as String,
          criminalId: row['criminal_id'] as String?,
          type: MediaType.fromString(row['type'] as String),
          filePath: row['file_path'] as String,
          caption: row['caption'] as String,
          sourceItemId: row['source_item_id'] as String?,
          isSynthetic: (row['is_synthetic'] as num).toInt() == 1,
          createdAt: (row['created_at'] as num).toInt(),
          uploadedByInvestigatorId:
              row['uploaded_by_investigator_id'] as String? ?? 'system',
          deletedAt: (row['deleted_at'] as num?)?.toInt(),
        ));
      }

      // Pull text records
      final textRes = await conn.execute(
        Sql.named('''
          SELECT id, criminal_id, kind, title, body, created_at, synced_at
          FROM shared_text_records
          WHERE synced_at > @lastTs
          ORDER BY synced_at ASC
        '''),
        parameters: {'lastTs': lastServerTs},
      );

      final textRecords = <TextRecord>[];
      for (final r in textRes) {
        final row = r.toColumnMap();
        final syncedAt = (row['synced_at'] as num).toInt();
        if (syncedAt > maxTs) maxTs = syncedAt;

        textRecords.add(TextRecord(
          id: row['id'] as String,
          criminalId: row['criminal_id'] as String?,
          kind: TextRecordKind.fromString(row['kind'] as String),
          title: row['title'] as String,
          body: row['body'] as String,
          createdAt: (row['created_at'] as num).toInt(),
        ));
      }

      return RemoteSyncPullResult(
        criminals: criminals,
        caseNotes: caseNotes,
        mediaItems: mediaItems,
        textRecords: textRecords,
        maxServerTs: maxTs,
      );
    } finally {
      await conn?.close();
    }
  }

  @override
  Future<List<CanonicalAuditEntry>> fetchCanonicalLogs({int limit = 50}) async {
    if (!isConfigured) return const [];
    Connection? conn;
    try {
      conn = await _openConnection();
      final res = await conn.execute(
        Sql.named('''
          SELECT seq, device_id, local_seq, actor, action, target_type, target_id,
                 payload_hash, local_ts, server_ts, prev_hash, entry_hash, payload_json
          FROM central_audit_log
          ORDER BY seq DESC
          LIMIT @limit
        '''),
        parameters: {'limit': limit},
      );

      return res.map((r) {
        final row = r.toColumnMap();
        return CanonicalAuditEntry(
          seq: (row['seq'] as num).toInt(),
          deviceId: row['device_id'] as String,
          localSeq: (row['local_seq'] as num).toInt(),
          actor: LogActor.fromString(row['actor'] as String),
          action: LogAction.fromString(row['action'] as String),
          targetType: row['target_type'] as String,
          targetId: row['target_id'] as String,
          payloadHash: row['payload_hash'] as String,
          localTs: (row['local_ts'] as num).toInt(),
          serverTs: (row['server_ts'] as num).toInt(),
          prevHash: row['prev_hash'] as String,
          entryHash: row['entry_hash'] as String,
          payloadJson: row['payload_json'] as String?,
        );
      }).toList();
    } finally {
      await conn?.close();
    }
  }

  @override
  Future<bool> verifyCanonicalChain() async {
    if (!isConfigured) return true;
    Connection? conn;
    try {
      conn = await _openConnection();
      final res = await conn.execute(
        'SELECT seq, device_id, actor, action, target_type, target_id, payload_hash, local_ts, server_ts, prev_hash, entry_hash FROM central_audit_log ORDER BY seq ASC',
      );

      var expectedSeq = 1;
      var expectedPrevHash = AppConstants.genesisHash;

      for (final r in res) {
        final row = r.toColumnMap();
        final seq = (row['seq'] as num).toInt();
        final deviceId = row['device_id'] as String;
        final actor = LogActor.fromString(row['actor'] as String);
        final action = LogAction.fromString(row['action'] as String);
        final targetType = row['target_type'] as String;
        final targetId = row['target_id'] as String;
        final payloadHash = row['payload_hash'] as String;
        final localTs = (row['local_ts'] as num).toInt();
        final serverTs = (row['server_ts'] as num).toInt();
        final prevHash = row['prev_hash'] as String;
        final entryHash = row['entry_hash'] as String;

        if (seq != expectedSeq) return false;
        if (prevHash != expectedPrevHash) return false;

        final recomputed = CanonicalAuditEntry.computeEntryHash(
          seq: seq,
          deviceId: deviceId,
          actor: actor,
          action: action,
          targetType: targetType,
          targetId: targetId,
          payloadHash: payloadHash,
          localTs: localTs,
          serverTs: serverTs,
          prevHash: prevHash,
        );

        if (recomputed != entryHash) return false;

        expectedSeq = seq + 1;
        expectedPrevHash = entryHash;
      }

      return true;
    } catch (_) {
      return false;
    } finally {
      await conn?.close();
    }
  }
}
