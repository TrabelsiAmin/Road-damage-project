import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// SQLite database helper for TariqMap.
///
/// Single-instance via [AppDatabase.instance].
/// Migrations are versioned; add a new block in [_onUpgrade] for each schema change.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _open();
    return _db!;
  }

  static const _dbName    = 'tariqmap.db';
  static const _dbVersion = 1;

  // ── Schema ────────────────────────────────────────────────────────────────

  static const _createObservations = '''
    CREATE TABLE IF NOT EXISTS observations (
      id                  TEXT PRIMARY KEY,
      capture_id          TEXT NOT NULL,
      image_path          TEXT NOT NULL,
      annotated_image_path TEXT,
      created_at          TEXT NOT NULL,
      latitude            REAL NOT NULL,
      longitude           REAL NOT NULL,
      accuracy_meters     REAL,
      actor               TEXT NOT NULL,
      sync_status         TEXT NOT NULL DEFAULT 'pending',
      sync_error          TEXT,
      upload_attempts     INTEGER NOT NULL DEFAULT 0,
      model_bundle_version TEXT NOT NULL,
      device_id           TEXT,
      image_width         INTEGER,
      image_height        INTEGER,
      priority_score      REAL,
      failed_agents       INTEGER NOT NULL DEFAULT 0,
      any_mock            INTEGER NOT NULL DEFAULT 1
    )
  ''';

  static const _createDetections = '''
    CREATE TABLE IF NOT EXISTS detections (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      observation_id TEXT NOT NULL REFERENCES observations(id) ON DELETE CASCADE,
      agent         TEXT NOT NULL,
      class_code    TEXT NOT NULL,
      confidence    REAL NOT NULL,
      box_x         REAL NOT NULL,
      box_y         REAL NOT NULL,
      box_w         REAL NOT NULL,
      box_h         REAL NOT NULL,
      frame_index   INTEGER,
      model_version TEXT,
      detected_at   TEXT
    )
  ''';

  static const _createAgentResults = '''
    CREATE TABLE IF NOT EXISTS agent_results (
      id             INTEGER PRIMARY KEY AUTOINCREMENT,
      observation_id TEXT NOT NULL REFERENCES observations(id) ON DELETE CASCADE,
      agent          TEXT NOT NULL,
      error          TEXT,
      is_mock        INTEGER NOT NULL DEFAULT 1,
      latency_ms     INTEGER
    )
  ''';

  static const _createAuditLog = '''
    CREATE TABLE IF NOT EXISTS audit_log (
      id             INTEGER PRIMARY KEY AUTOINCREMENT,
      observation_id TEXT,
      event          TEXT NOT NULL,
      detail         TEXT,
      occurred_at    TEXT NOT NULL
    )
  ''';

  // ── Open / migrate ────────────────────────────────────────────────────────

  Future<Database> _open() async {
    if (kIsWeb) {
      throw UnsupportedError('SQLite is not supported on web. Use MemoryObservationRepository.');
    }
    final dbPath = p.join(await getDatabasesPath(), _dbName);
    debugPrint('[AppDatabase] Opening: $dbPath');
    return openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate:  _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.execute('PRAGMA journal_mode = WAL');
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute(_createObservations);
    await db.execute(_createDetections);
    await db.execute(_createAgentResults);
    await db.execute(_createAuditLog);
    debugPrint('[AppDatabase] Schema created at version $version');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Add migration blocks here for future schema versions.
    // e.g.: if (oldVersion < 2) { await db.execute('ALTER TABLE ...'); }
    debugPrint('[AppDatabase] Migrating $oldVersion → $newVersion');
  }

  // ── Utilities ─────────────────────────────────────────────────────────────

  Future<void> close() async => _db?.close();

  Future<int> rowCount(String table) async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as c FROM $table');
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
