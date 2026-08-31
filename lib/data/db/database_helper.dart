import 'dart:async';
import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../core/constants/constants.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  static bool _ffiInitialized = false;

  DatabaseHelper._init();

  /// Initialize FFI factory for desktop platforms (Windows, Linux, macOS)
  static void initFfi() {
    if (!_ffiInitialized) {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }
      _ffiInitialized = true;
    }
  }

  Future<Database> get database async {
    final db = _database;
    if (db != null) return db;
    _database = await _initDB(AppConstants.defaultDatabaseName);
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    initFfi();

    String dbPath;
    try {
      final appDir = await getApplicationSupportDirectory();
      dbPath = join(appDir.path, filePath);
    } catch (_) {
      // Fallback if path_provider fails in non-GUI / test context
      dbPath = join(Directory.current.path, filePath);
    }

    // Ensure parent directory exists
    final parentDir = Directory(dirname(dbPath));
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    return await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: _createDB,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
      ),
    );
  }

  /// Initialize an in-memory database for testing purposes
  static Future<Database> initInMemoryDatabase() async {
    initFfi();
    return await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await DatabaseHelper.instance._createDB(db, version);
        },
      ),
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // 1. Criminals Table
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

    // 2. Media Items Table
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

    // 3. Structured Records: CDR
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

    // 4. Structured Records: Financial Txns
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

    // 5. Structured Records: Criminal History
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

    // 6. Unstructured Text Records (FIR, Intel)
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

    // 7. Graph Entities
    await db.execute('''
      CREATE TABLE entities (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        value TEXT NOT NULL,
        firstSeenIn TEXT NOT NULL
      )
    ''');

    // 8. Graph Edges
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

    // 9. Case Notes
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

    // 10. News Attachments
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

    // 11. Immutable Hash-Chained Audit Log
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

    // 12. Investigators (Local auth)
    await db.execute('''
      CREATE TABLE investigators (
        id TEXT PRIMARY KEY,
        displayName TEXT NOT NULL,
        email TEXT NOT NULL,
        faceEmbeddings TEXT NOT NULL,
        createdAt INTEGER NOT NULL
      )
    ''');

    // 13. RAG Vector Chunks
    await db.execute('''
      CREATE TABLE vector_chunks (
        id TEXT PRIMARY KEY,
        sourceType TEXT NOT NULL,
        sourceId TEXT NOT NULL,
        text TEXT NOT NULL,
        embedding TEXT NOT NULL
      )
    ''');

    // Indexes for fast querying
    await db.execute('CREATE INDEX idx_criminals_status ON criminals (status)');
    await db.execute('CREATE INDEX idx_cdr_criminal ON cdr_records (criminalId)');
    await db.execute('CREATE INDEX idx_financial_criminal ON financial_txns (criminalId)');
    await db.execute('CREATE INDEX idx_text_criminal ON text_records (criminalId)');
    await db.execute('CREATE INDEX idx_notes_criminal ON case_notes (criminalId)');
    await db.execute('CREATE INDEX idx_log_seq ON log_entries (seq)');
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
