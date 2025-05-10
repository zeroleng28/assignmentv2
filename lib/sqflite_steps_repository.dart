import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'db_helper.dart';
import 'step_entry.dart';

class SqfliteStepsRepository {
  final DbHelper _db = DbHelper();

  Future<void> upsert(StepEntry e) async {
    final db = await _db.database;
    print("► try insert steps: ${e.day} → ${e.count}");
    final id = await db.insert(
      'steps',
      e.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    print("✓ steps insert success, id = $id");

    // Firestore 同步（可选调试）
    await FirebaseFirestore.instance
        .collection('steps')
        .doc(e.id)
        .set({
      'user_email': e.user_email,
      'day'       : DateFormat('yyyy-MM-dd').format(e.day),
      'count'     : e.count,
      'createdAt' : e.createdAt.toIso8601String(),
      'updatedAt' : e.updatedAt.toIso8601String(),
    });
  }


  Future<List<StepEntry>> fetchLast7Days(String user_email) async {
    final db = await _db.database;
    final cutoff = DateTime.now().subtract(const Duration(days: 6));
    final rows = await db.query(
      'steps',
      where: 'user_email = ? AND day >= ?',
      whereArgs: [user_email, cutoff.toIso8601String().substring(0, 10)],
      orderBy: 'day ASC',
    );
    return rows.map((r) => StepEntry.fromMap(r)).toList();
  }

  /// Returns a list of StepEntry with one record per month (last 6 months).
  Future<List<StepEntry>> fetchMonthlyTotals(String user_email) async {
    final db     = await _db.database;
    // get rows grouped by YYYY-MM
    final rows   = await db.rawQuery('''
    SELECT substr(day,1,7) AS ym, SUM(count) AS total,
           MIN(day)           AS daySample,
           MAX(updatedAt)     AS updatedAt
      FROM steps
     WHERE user_email = ?
     GROUP BY ym
     ORDER BY ym DESC
     LIMIT 6
  ''');
    return rows.map((r) {
      final ym = r['ym'] as String;               // "2025-05"
      return StepEntry(
        id        : ym,                            // use ym for id
        user_email: user_email,
        day       : DateTime.parse('$ym-01'),      // first day of month
        count     : (r['total'] as num).toDouble(),
        createdAt : DateTime.parse(r['daySample'] as String),
        updatedAt : DateTime.parse(r['updatedAt'] as String),
      );
    }).toList();
  }
}

