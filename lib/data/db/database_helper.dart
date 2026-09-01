import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/constants/constants.dart';
import '../../core/errors/app_exceptions.dart';

/// Opens and creates the local SQLite database.
///
/// Was a singleton holding a static `_database`, which meant a test that
/// opened an in-memory database could poison the next test through the shared
/// static. It is now an ordinary class: [open] returns a handle, and whoever
/// opened it owns it.
class DatabaseHelper {
  static bool _ffiReady = false;

  /// Installs the FFI factory needed for SQLite on desktop. Idempotent, and
  /// safe to call from tests before any database is opened.
  static void initFfi() {
    if (_ffiReady) return;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    _ffiReady = true;
  }

  /// Opens the on-disk database, creating the schema on first run.
  Future<Database> open({String? fileName}) async {
    initFfi();

    final name = fileName ?? AppConstants.defaultDatabaseName;
    String path;
    try {
      final dir = await getApplicationSupportDirectory();
      path = join(dir.path, name);
    } catch (_) {
      // path_provider needs a platform channel, which is absent in plain
      // Dart tests. Fall back to the working directory.
      path = join(Directory.current.path, name);
    }

    try {
      final parent = Directory(dirname(path));
      if (!await parent.exists()) await parent.create(recursive: true);

      return await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: createSchema,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        ),
      );
    } catch (error) {
      throw DataAccessException(
        'Could not open the case database at $path.',
        cause: error,
      );
    }
  }

  /// Opens a throwaway in-memory database with the full schema, for tests.
  static Future<Database> openInMemory() async {
    initFfi();
    return databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: createSchema,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      ),
    );
  }

  /// Creates every table in `docs/Schema.md`.
  static Future<void> createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE criminals (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        aliases TEXT NOT NULL,
        dob TEXT NOT NULL,
        gender TEXT NOT NULL,
        knownFor TEXT NOT NULL,
        status TEXT NOT NULL,
        lastKnownLoc TEXT NOT NULL,
        riskLevel TEXT NOT NULL,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL,
        isDeleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE media_items (
        id TEXT PRIMARY KEY,
        criminalId TEXT,
        type TEXT NOT NULL,
        filePath TEXT NOT NULL,
        caption TEXT NOT NULL,
        sourceItemId TEXT,
        isSynthetic INTEGER NOT NULL DEFAULT 1,
        createdAt INTEGER NOT NULL,
        FOREIGN KEY (criminalId) REFERENCES criminals (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE cdr_records (
        id TEXT PRIMARY KEY,
        criminalId TEXT NOT NULL,
        callerId TEXT NOT NULL,
        calleeId TEXT NOT NULL,
        ts INTEGER NOT NULL,
        durationSec INTEGER NOT NULL,
        cellSite TEXT NOT NULL,
        FOREIGN KEY (criminalId) REFERENCES criminals (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE financial_txns (
        id TEXT PRIMARY KEY,
        criminalId TEXT NOT NULL,
        counterparty TEXT NOT NULL,
        amount REAL NOT NULL,
        currency TEXT NOT NULL DEFAULT 'INR',
        ts INTEGER NOT NULL,
        channel TEXT NOT NULL,
        FOREIGN KEY (criminalId) REFERENCES criminals (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE criminal_history (
        id TEXT PRIMARY KEY,
        criminalId TEXT NOT NULL,
        offense TEXT NOT NULL,
        date TEXT NOT NULL,
        dispositionNote TEXT NOT NULL,
        FOREIGN KEY (criminalId) REFERENCES criminals (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE text_records (
        id TEXT PRIMARY KEY,
        criminalId TEXT,
        kind TEXT NOT NULL,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        createdAt INTEGER NOT NULL,
        FOREIGN KEY (criminalId) REFERENCES criminals (id)
      )
    ''');

    // Derived by GraphService from the records above; never hand-authored.
    await db.execute('''
      CREATE TABLE entities (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        value TEXT NOT NULL,
        firstSeenIn TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE edges (
        id TEXT PRIMARY KEY,
        srcEntityId TEXT NOT NULL,
        dstEntityId TEXT NOT NULL,
        relation TEXT NOT NULL,
        weight INTEGER NOT NULL DEFAULT 1,
        evidenceIds TEXT NOT NULL,
        FOREIGN KEY (srcEntityId) REFERENCES entities (id),
        FOREIGN KEY (dstEntityId) REFERENCES entities (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE case_notes (
        id TEXT PRIMARY KEY,
        criminalId TEXT NOT NULL,
        author TEXT NOT NULL,
        text TEXT NOT NULL,
        createdAt INTEGER NOT NULL,
        FOREIGN KEY (criminalId) REFERENCES criminals (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE news_attachments (
        id TEXT PRIMARY KEY,
        criminalId TEXT NOT NULL,
        title TEXT NOT NULL,
        url TEXT NOT NULL,
        imagePath TEXT,
        attachedBy TEXT NOT NULL,
        createdAt INTEGER NOT NULL,
        FOREIGN KEY (criminalId) REFERENCES criminals (id)
      )
    ''');

    // Append-only. There is no UPDATE or DELETE against this table anywhere
    // in the codebase, and none may be added (`docs/Rules.md` §2).
    await db.execute('''
      CREATE TABLE log_entries (
        seq INTEGER PRIMARY KEY,
        actor TEXT NOT NULL,
        action TEXT NOT NULL,
        targetType TEXT NOT NULL,
        targetId TEXT NOT NULL,
        payloadHash TEXT NOT NULL,
        ts INTEGER NOT NULL,
        prevHash TEXT NOT NULL,
        entryHash TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE investigators (
        id TEXT PRIMARY KEY,
        displayName TEXT NOT NULL,
        email TEXT NOT NULL,
        faceEmbeddings TEXT NOT NULL,
        createdAt INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE vector_chunks (
        id TEXT PRIMARY KEY,
        sourceType TEXT NOT NULL,
        sourceId TEXT NOT NULL,
        text TEXT NOT NULL,
        embedding TEXT NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_criminals_status ON criminals (status)');
    await db.execute('CREATE INDEX idx_cdr_criminal ON cdr_records (criminalId)');
    await db
        .execute('CREATE INDEX idx_financial_criminal ON financial_txns (criminalId)');
    await db.execute('CREATE INDEX idx_text_criminal ON text_records (criminalId)');
    await db.execute('CREATE INDEX idx_notes_criminal ON case_notes (criminalId)');
    await db.execute('CREATE INDEX idx_log_seq ON log_entries (seq)');
    await db.execute('CREATE INDEX idx_vector_source ON vector_chunks (sourceType)');
  }
}
