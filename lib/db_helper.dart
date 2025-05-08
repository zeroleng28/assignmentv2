import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
import 'habit_entry.dart';

class DbHelper {
  static final DbHelper _instance = DbHelper._();
  factory DbHelper() => _instance;
  DbHelper._();

  static const _dbName = 'habits.db';
  static const _dbVersion = 7;

  Future<void> deleteAllEntries() async {
    final db = await database;
    await db.delete('entries');
  }

  Future<Database> openDb() async {
    return openDatabase(
      join(await getDatabasesPath(), 'steps.db'),
      onCreate: (db, version) {
        return db.execute(
          'CREATE TABLE steps(id INTEGER PRIMARY KEY, value INTEGER, timestamp INTEGER)',
        );
      },
      version: 1,
    );
  }

  /// Return the most‑recent Short‑Walk total saved for *today*.
  /// If no row exists yet, return null.
  Future<int?> getLastSavedSteps() async {
    final db = await database;
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final row = await db.query(
      'entries',
      where: 'habitTitle = ? AND substr(date,1,10) = ?',
      whereArgs: ['Short Walk', todayKey],
      orderBy: 'updatedAt DESC',
      limit: 1,
    );

    if (row.isEmpty) return null;
    return (row.first['value'] as num).toInt();
  }

  /// Overwrite today's Short‑Walk row with the new total.
  Future<void> saveSteps(int steps) async {
    final db = await database;
    final today = DateTime.now();
    final ymd  = DateFormat('yyyy-MM-dd').format(today);

    await db.delete(
      'entries',
      where: 'habitTitle = ? AND substr(date,1,10) = ?',
      whereArgs: ['Short Walk', ymd],
    );

    await db.insert('entries', {
      'id'        : const Uuid().v4(),
      'habitTitle': 'Short Walk',
      'date'      : today.toIso8601String(),
      'value'     : steps,
      'createdAt' : DateTime.now().toIso8601String(),
      'updatedAt' : DateTime.now().toIso8601String(),
    });
  }

  Future<void> deleteDay(String habitTitle, DateTime date) async {
    final db = await database;
    final key = DateFormat('yyyy-MM-dd').format(date);     // "2025-05-05"
    await db.delete(
      'entries',
      where: 'habitTitle = ? AND substr(date,1,10) = ?',   // YYYY-MM-DD
      whereArgs: [habitTitle, key],
    );
  }

  Future<void> deleteDatabaseFile() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);
    await deleteDatabase(path);
  }

  Database? _database;
  Future<Database> get database async {
    if (_database != null) return _database!;
    final path = join(await getDatabasesPath(), _dbName);
    _database = await openDatabase(
      path,
      version: _dbVersion,
      onConfigure: _onConfigure,
      onCreate:    _onCreate,
      onUpgrade:   _onUpgrade,
    );
    return _database!;
  }

  Future<void> clearEntriesForHabit(String habitTitle) async {
    final db = await database;
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 6))
        .toIso8601String();
    await db.delete(
      'entries',
      where: 'habitTitle = ? AND date >= ?',
      whereArgs: [habitTitle, cutoff],
    );
  }

  /// Inspect existing table and migrate only if 'date' is not TEXT.
  Future<void> _onConfigure(Database db) async {
    final info = await db.rawQuery("PRAGMA table_info('entries')");
    // If table exists and date column is not TEXT, migrate:
    if (info.isNotEmpty && !info.any((c) => c['name'] == 'date' && c['type'] == 'TEXT')) {
      await db.execute('ALTER TABLE entries RENAME TO entries_old');
      await _onCreate(db, _dbVersion);
      await db.execute('''
        INSERT INTO entries (id, habitTitle, date, value, createdAt, updatedAt)
        SELECT id, habitTitle, date, value, createdAt, updatedAt
        FROM entries_old;
      ''');
      await db.execute('DROP TABLE entries_old');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE entries (
        id         TEXT PRIMARY KEY,
        habitTitle TEXT,
        date       TEXT,
        value      REAL,
        createdAt  TEXT,
        updatedAt  TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    await db.execute('DROP TABLE IF EXISTS entries');
    await db.execute('''
    CREATE TABLE entries (
      id         TEXT PRIMARY KEY,
      habitTitle TEXT,
      date       TEXT,
      value      REAL,
      createdAt  TEXT,
      updatedAt  TEXT
    )
  ''');
  }


  /// Insert or replace an entry, storing all dates as ISO-8601 strings.
  Future<void> upsertEntry(HabitEntry entry) async {
    final db = await database;
    await db.insert(
      'entries',
      {
        'id':        entry.id,
        'habitTitle': entry.habitTitle,
        'date':      entry.date.toIso8601String(),
        'value':     entry.value,
        'createdAt': entry.createdAt.toIso8601String(),
        'updatedAt': entry.updatedAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Fetch last 7 days for the given habit, parsing ISO strings back to DateTime.
  Future<List<HabitEntry>> fetchLast7Days(String habitTitle) async {
    final db = await database;
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 6))
        .toIso8601String();

    final rows = await db.query(
      'entries',
      where: 'habitTitle = ? AND date >= ?',
      whereArgs: [habitTitle, cutoff],
      orderBy: 'date ASC',
    );

    return rows.map((r) {
      return HabitEntry(
        id:         r['id'] as String,
        habitTitle: r['habitTitle'] as String,
        date:       DateTime.parse(r['date'] as String),
        value:      (r['value'] as num).toDouble(),
        createdAt:  DateTime.parse(r['createdAt'] as String),
        updatedAt:  DateTime.parse(r['updatedAt'] as String),
      );
    }).toList();
  }

  /// Group entries by month (YYYY-MM) and sum values.
  Future<List<HabitEntry>> fetchMonthlyTotals(String habitTitle) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT
        substr(date,1,7) AS ym,
        SUM(value)      AS total
      FROM entries
      WHERE habitTitle = ?
      GROUP BY ym
      ORDER BY ym ASC
      ''',
      [habitTitle],
    );

    return rows.map((r) {
      final ym = r['ym'] as String;      // e.g. "2025-05"
      final parts = ym.split('-');
      final year  = int.parse(parts[0]);
      final month = int.parse(parts[1]);

      return HabitEntry(
        id:         '$habitTitle-$ym',
        habitTitle: habitTitle,
        date:       DateTime(year, month),
        value:      (r['total'] as num).toDouble(),
        createdAt:  DateTime.now(),
        updatedAt:  DateTime.now(),
      );
    }).toList();
  }

  Future<void> clearEntries() async {
    final db = await database;
    await db.delete('entries');
  }

  Future<void> dropAndRecreateEntriesTable() async {
    final db = await database;
    await db.execute('DROP TABLE IF EXISTS entries');
    await db.execute('''
    CREATE TABLE entries (
      id         TEXT PRIMARY KEY,
      habitTitle TEXT,
      date       TEXT,
      value      REAL,
      createdAt  TEXT,
      updatedAt  TEXT
    )
  ''');
  }

  Future<List<HabitEntry>> fetchRange(String habitTitle, DateTime pivot) async {
    final db = await database;
    final start = DateTime(pivot.year, pivot.month, pivot.day)
        .subtract(const Duration(days: 6))
        .toIso8601String();
    final end   = DateTime(pivot.year, pivot.month, pivot.day, 23, 59, 59)
        .toIso8601String();

    final rows = await db.query(
      'entries',
      where: 'habitTitle = ? AND date BETWEEN ? AND ?',
      whereArgs: [habitTitle, start, end],
      orderBy: 'date ASC',
    );

    return rows.map((r) => HabitEntry(
      id:         r['id'] as String,
      habitTitle: r['habitTitle'] as String,
      date:       DateTime.parse(r['date'] as String),
      value:      (r['value'] as num).toDouble(),
      createdAt:  DateTime.parse(r['createdAt'] as String),
      updatedAt:  DateTime.parse(r['updatedAt'] as String),
    )).toList();
  }
}