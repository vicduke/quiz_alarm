/// Opens the app's SQLite database and owns its schema.
///
/// Tables:
/// - `units`      course units (Pharmacology, ...)
/// - `topics`     subtopics of a unit
/// - `questions`  questions with their answer AND explanation, so the
///                bank works fully offline
/// - `attempts`   every answer the user gave, with what they answered and
///                how long it took (drives "not asked yet", progress,
///                weak-question selection and the reports)
/// - `sessions`   one row per alarm ring or practice session, so the
///                reports can show history and time-to-wake
/// - `meta`       small key/value store (seed versions)
library;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  static const int schemaVersion = 2;
  static const String fileName = 'brainwake.db';

  static Database? _db;
  static Future<Database>? _opening;

  /// Replaces the phone's SQLite. Tests set it to an in-memory database;
  /// the browser emulator (tool/emulator/main.dart) sets it to SQLite
  /// compiled for the web.
  static DatabaseFactory? factoryOverride;
  static String? pathOverride;

  static Future<Database> get instance {
    final db = _db;
    if (db != null) return Future.value(db);
    return _opening ??= _open();
  }

  static Future<Database> _open() async {
    final factory = factoryOverride ?? databaseFactory;
    final path =
        pathOverride ??
        (kIsWeb
            ? fileName
            : p.join(await factory.getDatabasesPath(), fileName));
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => _create(db),
        onUpgrade: _upgrade,
      ),
    );
    _db = db;
    return db;
  }

  static Future<void> _create(Database db) async {
    final batch = db.batch();
    batch.execute('''
      CREATE TABLE units(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        sort_order INTEGER NOT NULL DEFAULT 0
      )''');
    batch.execute('''
      CREATE TABLE topics(
        id TEXT PRIMARY KEY,
        unit_id TEXT NOT NULL REFERENCES units(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        is_custom INTEGER NOT NULL DEFAULT 0
      )''');
    batch.execute('''
      CREATE TABLE questions(
        id TEXT PRIMARY KEY,
        topic_id TEXT NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
        type TEXT NOT NULL,
        text TEXT NOT NULL,
        text_key TEXT NOT NULL,
        options TEXT NOT NULL DEFAULT '[]',
        answer TEXT NOT NULL,
        alt_answers TEXT NOT NULL DEFAULT '[]',
        explanation TEXT NOT NULL DEFAULT '',
        source TEXT NOT NULL DEFAULT 'seed',
        created_at INTEGER NOT NULL
      )''');
    batch.execute(
      'CREATE UNIQUE INDEX idx_questions_unique ON questions(topic_id, text_key)',
    );
    batch.execute('''
      CREATE TABLE attempts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        question_id TEXT NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
        mode TEXT NOT NULL,
        correct INTEGER NOT NULL,
        answered_at INTEGER NOT NULL,
        session_id INTEGER REFERENCES sessions(id) ON DELETE SET NULL,
        user_answer TEXT NOT NULL DEFAULT '',
        duration_ms INTEGER
      )''');
    batch.execute(_createSessions);
    batch.execute(
      'CREATE INDEX idx_attempts_question ON attempts(question_id)',
    );
    batch.execute(
      'CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    await batch.commit(noResult: true);
  }

  static const String _createSessions = '''
    CREATE TABLE sessions(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      kind TEXT NOT NULL,
      title TEXT NOT NULL,
      alarm_id INTEGER,
      required_streak INTEGER,
      started_at INTEGER NOT NULL,
      ended_at INTEGER,
      outcome TEXT
    )''';

  /// Brings an older database up to date without losing anything.
  static Future<void> _upgrade(Database db, int from, int to) async {
    if (from < 2) {
      await db.execute(_createSessions);
      await db.execute(
        'ALTER TABLE attempts ADD COLUMN session_id INTEGER '
        'REFERENCES sessions(id) ON DELETE SET NULL',
      );
      await db.execute(
        "ALTER TABLE attempts ADD COLUMN user_answer TEXT NOT NULL DEFAULT ''",
      );
      await db.execute('ALTER TABLE attempts ADD COLUMN duration_ms INTEGER');
    }
  }

  /// Closes the database (tests use this between cases).
  @visibleForTesting
  static Future<void> close() async {
    final db = _db ?? await _opening;
    _db = null;
    _opening = null;
    await db?.close();
  }
}
