import 'package:sqflite/sqflite.dart';
import 'habits_repository.dart';
import 'db_helper.dart';
import 'habit_entry.dart';
import 'sync_service.dart';

class SqfliteHabitsRepository implements HabitsRepository {
  final DbHelper _db = DbHelper();

  // @override
  // Future<void> upsertEntry(HabitEntry entry) async {
  //   await _db.upsertEntry(entry);
  //   await SyncService().pushEntry(entry);
  // }

  @override
  Future<void> upsertEntry(HabitEntry entry) async {
    try {
      final db = await DbHelper().database;
      print("► try insert entries: ${entry.habitTitle} on ${entry.date}");
      final id = await db.insert(
        'entries',
        entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      print("✓ insert success, returned id = $id");
    } catch (e, st) {
      print("✗ insert failed: $e\n$st");
    }
  }


  @override
  Future<List<HabitEntry>> fetchLast7Days(String user_email, String habitTitle) =>
      _db.fetchLast7Days(user_email, habitTitle);

  @override
  Future<List<HabitEntry>> fetchMonthlyTotals(String user_email, String habitTitle) =>
      _db.fetchMonthlyTotals(user_email, habitTitle);

  @override
  Future<void> clearEntries() => _db.clearEntries();

  @override
  Future<void> clearEntriesForHabit(String habitTitle) =>
      _db.clearEntriesForHabit(habitTitle);

  @override
  Future<List<HabitEntry>> fetchRange(String user_email, String habitTitle, DateTime pivotDate) =>
      _db.fetchRange(user_email, habitTitle, pivotDate);

  @override
  Future<void> deleteDay(String habitTitle, DateTime date) =>
      _db.deleteDay(habitTitle, date);

}
