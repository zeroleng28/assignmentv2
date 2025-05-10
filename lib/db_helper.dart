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
  static const _dbVersion = 8;

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

  // Proper implementation for getting today's step count
  Future<int?> getLastSavedSteps() async {
    final db = await database;
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final rows = await db.query(
      'steps',
      where: 'day = ?',
      whereArgs: [todayKey],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return (rows.first['count'] as num).toInt();
  }

  /// Overwrite today's Short‑Walk row with the new total.
  Future<void> saveSteps(int steps, String user_email) async {
    final db = await database;
    final today = DateTime.now();
    final ymd = DateFormat('yyyy-MM-dd').format(today);

    await db.delete(
      'entries',
      where: 'habitTitle = ? AND substr(date,1,10) = ?',
      whereArgs: ['Short Walk', ymd],
    );

    await db.insert('entries', {
      'id': const Uuid().v4(),
      'user_email': user_email,
      'habitTitle': 'Short Walk',
      'date': today.toIso8601String(),
      'value': steps,
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> deleteDay(String habitTitle, DateTime date) async {
    final db = await database;
    final key = DateFormat('yyyy-MM-dd').format(date); // "2025-05-05"
    await db.delete(
      'entries',
      where: 'habitTitle = ? AND substr(date,1,10) = ?', // YYYY-MM-DD
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
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return _database!;
  }

  Future<void> clearEntriesForHabit(String habitTitle) async {
    final db = await database;
    final cutoff =
        DateTime.now().subtract(const Duration(days: 6)).toIso8601String();
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
    if (info.isNotEmpty &&
        !info.any((c) => c['name'] == 'date' && c['type'] == 'TEXT')) {
      await db.execute('ALTER TABLE entries RENAME TO entries_old');
      await _onCreate(db, _dbVersion);
      await db.execute('''
        INSERT INTO entries (id, user_email, habitTitle, date, value, createdAt, updatedAt)
        SELECT id, user_email, habitTitle, date, value, createdAt, updatedAt
        FROM entries_old;
      ''');
      await db.execute('DROP TABLE entries_old');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    // Create your existing entries table
    await db.execute('''
    CREATE TABLE users (
      email     TEXT PRIMARY KEY NOT NULL,
      username  TEXT,
      phone     TEXT,
      location  TEXT
    );
  ''');
    await db.execute('''
    CREATE TABLE entries (
      id         TEXT PRIMARY KEY,
      user_email TEXT NOT NULL,
      habitTitle TEXT,
      date       TEXT,
      value      REAL,
      createdAt  TEXT,
      updatedAt  TEXT,
      FOREIGN KEY(user_email) REFERENCES users(email) ON DELETE CASCADE
    )
  ''');

    // Create the new steps table
    await db.execute('''
    CREATE TABLE steps (
      id         TEXT    PRIMARY KEY,
      user_email TEXT    NOT NULL,  
      day        TEXT    NOT NULL,
      count      REAL    NOT NULL,
      createdAt  TEXT    NOT NULL,
      updatedAt  TEXT    NOT NULL,
      FOREIGN KEY(user_email) REFERENCES users(email) ON DELETE CASCADE
    )
  ''');

    // Add a unique index on the day column
    await db.execute('''
    CREATE UNIQUE INDEX idx_steps_day
      ON steps(day)
  ''');
    final seed = [
      {
        'email': 'alice@example.com',
        'username': 'Alice',
        'phone': '012-3456789',
        'location': 'Kuala Lumpur',
      },
    ];
  }

  Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    await db.execute('DROP TABLE IF EXISTS entries');
    await db.execute('''
    CREATE TABLE entries (
      id         TEXT PRIMARY KEY,
      user_email TEXT NOT NULL,
      habitTitle TEXT,
      date       TEXT,
      value      REAL,
      createdAt  TEXT,
      updatedAt  TEXT,
      FOREIGN KEY(user_email) REFERENCES users(email) ON DELETE CASCADE
    )
  ''');
    await db.execute('DROP TABLE IF EXISTS steps');
    await db.execute('''
   CREATE TABLE steps (
     id         TEXT    PRIMARY KEY,
     user_email TEXT    NOT NULL,
     day        TEXT    NOT NULL,
     count      REAL    NOT NULL,
     createdAt  TEXT    NOT NULL,
     updatedAt  TEXT    NOT NULL,
     FOREIGN KEY(user_email) REFERENCES users(email) ON DELETE CASCADE
   )
 ''');
  }

  /// Insert or replace an entry, storing all dates as ISO-8601 strings.
  Future<void> upsertEntry(HabitEntry entry) async {
    final db = await database;
    print(
      "► try insert entry: ${entry.habitTitle} @ ${entry.date.toIso8601String()}",
    );
    final id = await db.insert('entries', {
      'id': entry.id,
      'user_email': entry.user_email,
      'habitTitle': entry.habitTitle,
      'date': entry.date.toIso8601String(),
      'value': entry.value,
      'createdAt': entry.createdAt.toIso8601String(),
      'updatedAt': entry.updatedAt.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    print("✓ insert success, returned id: $id");
  }

  /// Fetch last 7 days for the given habit, parsing ISO strings back to DateTime.
  Future<List<HabitEntry>> fetchLast7Days(
    String user_email,
    String habitTitle,
  ) async {
    final db = await database;
    final cutoff =
        DateTime.now().subtract(const Duration(days: 6)).toIso8601String();

    final rows = await db.query(
      'entries',
      where: 'user_email = ? AND habitTitle = ? AND date >= ?',
      whereArgs: [user_email, habitTitle, cutoff],
      orderBy: 'date ASC',
    );

    return rows.map((r) {
      return HabitEntry(
        id: r['id'] as String,
        user_email: r['user_email'] as String,
        habitTitle: r['habitTitle'] as String,
        date: DateTime.parse(r['date'] as String),
        value: (r['value'] as num).toDouble(),
        createdAt: DateTime.parse(r['createdAt'] as String),
        updatedAt: DateTime.parse(r['updatedAt'] as String),
      );
    }).toList();
  }

  /// Group entries by month (YYYY-MM) and sum values.
  Future<List<HabitEntry>> fetchMonthlyTotals(
    String user_email,
    String habitTitle,
  ) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT
        substr(date,1,7) AS ym,
        SUM(value)      AS total
      FROM entries
      WHERE user_email = ?
      AND habitTitle = ?
      GROUP BY ym
      ORDER BY ym ASC
      ''',
      [user_email, habitTitle],
    );

    return rows.map((r) {
      final ym = r['ym'] as String; // e.g. "2025-05"
      final parts = ym.split('-');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);

      return HabitEntry(
        id: '$habitTitle-$ym',
        user_email: 'alice@example.com',
        habitTitle: habitTitle,
        date: DateTime(year, month),
        value: (r['total'] as num).toDouble(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
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
      user_email TEXT NOT NULL,
      habitTitle TEXT,
      date       TEXT,
      value      REAL,
      createdAt  TEXT,
      updatedAt  TEXT,
      FOREIGN KEY(user_email) REFERENCES users(email) ON DELETE CASCADE
    )
  ''');
  }

  Future<List<HabitEntry>> fetchRange(
    String user_email,
    String habitTitle,
    DateTime pivot,
  ) async {
    final db = await database;
    final start =
        DateTime(
          pivot.year,
          pivot.month,
          pivot.day,
        ).subtract(const Duration(days: 6)).toIso8601String();
    final end =
        DateTime(
          pivot.year,
          pivot.month,
          pivot.day,
          23,
          59,
          59,
        ).toIso8601String();

    final rows = await db.query(
      'entries',
      where: 'user_email = ? AND habitTitle = ? AND date BETWEEN ? AND ?',
      whereArgs: [user_email, habitTitle, start, end],
      orderBy: 'date ASC',
    );

    final List<HabitEntry> result = [];
    for (final r in rows) {
      // extract user_email and guard against null
      final userEmailStr = r['user_email'] as String?;
      if (userEmailStr == null) {
        // skip rows that somehow lack a user_email
        continue;
      }
      // also guard your other required fields
      final idStr = r['id'] as String?;
      final dateStr = r['date'] as String?;
      final created = r['createdAt'] as String?;
      final updated = r['updatedAt'] as String?;
      if (idStr == null ||
          dateStr == null ||
          created == null ||
          updated == null) {
        continue;
      }
      result.add(
        HabitEntry(
          id: idStr,
          user_email: userEmailStr,
          // ← now mapped
          habitTitle: r['habitTitle'] as String? ?? habitTitle,
          date: DateTime.parse(dateStr),
          value: (r['value'] as num? ?? 0).toDouble(),
          createdAt: DateTime.parse(created),
          updatedAt: DateTime.parse(updated),
        ),
      );
    }
    return result;
  }

  Future<List<HabitEntry>> fetchRangeLatest(
    String habit,
    DateTime pivot,
  ) async {
    final db = await database;
    final start =
        DateTime(
          pivot.year,
          pivot.month,
          pivot.day,
        ).subtract(const Duration(days: 6)).toIso8601String();
    final end =
        DateTime(
          pivot.year,
          pivot.month,
          pivot.day,
          23,
          59,
          59,
        ).toIso8601String();

    final rows = await db.rawQuery(
      '''
    SELECT e.*
    FROM entries e
    JOIN (
      SELECT substr(date,1,10) AS d, MAX(updatedAt) AS maxUpd
      FROM entries
      WHERE habitTitle = ? AND date BETWEEN ? AND ?
      GROUP BY d
    ) latest
    ON substr(e.date,1,10) = latest.d AND e.updatedAt = latest.maxUpd
    ORDER BY e.date ASC
  ''',
      [habit, start, end],
    );

    return rows
        .map(
          (r) => HabitEntry(
            id: r['id'] as String,
            user_email: r['user_email'] as String,
            habitTitle: r['habitTitle'] as String,
            date: DateTime.parse(r['date'] as String),
            value: (r['value'] as num).toDouble(),
            createdAt: DateTime.parse(r['createdAt'] as String),
            updatedAt: DateTime.parse(r['updatedAt'] as String),
          ),
        )
        .toList();
  }

  Future<void> dumpSchema() async {
    final db = await database;
    final tables = await db.rawQuery(
      "SELECT name, sql FROM sqlite_master WHERE type='table'",
    );
    print("=== tables ===");
    for (final row in tables) {
      print("${row['name']}: ${row['sql']}");
    }
  }

  Future<void> dumpCounts() async {
    final db = await database;
    for (final t in ['users', 'entries', 'steps']) {
      try {
        final cnt = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $t'),
        );
        print("count($t) = $cnt");
      } catch (e) {
        print("table $t missing: $e");
      }
    }
  }
}
