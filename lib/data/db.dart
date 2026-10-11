import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Encrypted relational database (SQLCipher, FRS-SEC-01, FRS-NFR-08).
class AppDb {
  static Database? _db;
  static const _name = 'epi.db';

  static Database get db {
    final d = _db;
    if (d == null) throw StateError('Database not open');
    return d;
  }

  static bool get isOpen => _db != null;

  static Future<Database> open(String key) async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, _name),
      password: key,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        for (final s in _schemaV1) {
          await db.execute(s);
        }
      },
    );
    return _db!;
  }

  /// Secure wipe: closes and deletes the encrypted file (FRS-SEC-10).
  static Future<void> wipe() async {
    final dir = await getDatabasesPath();
    await _db?.close();
    _db = null;
    await deleteDatabase(p.join(dir, _name));
  }

  static const _schemaV1 = <String>[
    '''CREATE TABLE settings(
      key TEXT PRIMARY KEY,
      value TEXT)''',
    '''CREATE TABLE facilities(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      code TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      governorate TEXT NOT NULL,
      district TEXT NOT NULL)''',
    '''CREATE TABLE children(
      id TEXT PRIMARY KEY,
      seq INTEGER NOT NULL UNIQUE,
      name TEXT NOT NULL,
      name_latin TEXT,
      sex TEXT NOT NULL CHECK(sex IN ('M','F')),
      dob TEXT NOT NULL,
      birth_weight INTEGER CHECK(birth_weight IS NULL OR (birth_weight BETWEEN 300 AND 7000)),
      facility_id INTEGER NOT NULL REFERENCES facilities(id),
      area TEXT,
      guardian_name TEXT NOT NULL,
      guardian_relation TEXT,
      phone TEXT,
      history_done INTEGER NOT NULL DEFAULT 0,
      voided INTEGER NOT NULL DEFAULT 0,
      void_reason TEXT,
      created_by TEXT NOT NULL,
      created_at TEXT NOT NULL,
      modified_by TEXT,
      modified_at TEXT)''',
    'CREATE INDEX ix_children_name ON children(name)',
    'CREATE INDEX ix_children_dob ON children(dob)',
    'CREATE INDEX ix_children_phone ON children(phone)',
    '''CREATE TABLE visits(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      child_id TEXT NOT NULL REFERENCES children(id),
      date TEXT NOT NULL,
      site TEXT NOT NULL CHECK(site IN ('fixed','outreach')),
      facility_id INTEGER REFERENCES facilities(id),
      worker TEXT NOT NULL,
      created_at TEXT NOT NULL)''',
    '''CREATE TABLE doses(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      child_id TEXT NOT NULL REFERENCES children(id),
      code TEXT NOT NULL,
      status TEXT NOT NULL CHECK(status IN ('given','not_given','unknown','campaign')),
      given_date TEXT,
      visit_id INTEGER REFERENCES visits(id),
      source TEXT NOT NULL CHECK(source IN ('visit','card','caregiver','campaign')),
      reason TEXT,
      campaign_name TEXT,
      rule_version TEXT NOT NULL,
      voided INTEGER NOT NULL DEFAULT 0,
      void_reason TEXT,
      created_by TEXT NOT NULL,
      created_at TEXT NOT NULL)''',
    'CREATE INDEX ix_doses_child ON doses(child_id)',
    "CREATE UNIQUE INDEX ux_dose_given ON doses(child_id, code) WHERE voided = 0 AND status = 'given'",
    '''CREATE TABLE calendar_events(
      child_id TEXT PRIMARY KEY REFERENCES children(id),
      event_id INTEGER NOT NULL)''',
    '''CREATE TABLE audit(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      ts TEXT NOT NULL,
      user TEXT NOT NULL,
      action TEXT NOT NULL,
      entity TEXT NOT NULL,
      entity_id TEXT,
      detail TEXT)''',
    "CREATE TRIGGER audit_no_update BEFORE UPDATE ON audit BEGIN SELECT RAISE(ABORT, 'audit log is append-only'); END",
    "CREATE TRIGGER audit_no_delete BEFORE DELETE ON audit BEGIN SELECT RAISE(ABORT, 'audit log is append-only'); END",
  ];
}
