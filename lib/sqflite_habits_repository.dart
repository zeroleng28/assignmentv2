import 'habits_repository.dart';
import 'db_helper.dart';
import 'habit_entry.dart';
import 'sync_service.dart';

class SqfliteHabitsRepository implements HabitsRepository {
  final DbHelper _db = DbHelper();

  @override
  Future<void> upsertEntry(HabitEntry entry) async {
    await _db.upsertEntry(entry);
    await SyncService().pushEntry(entry);
  }

  @override
  Future<List<HabitEntry>> fetchLast7Days(String habitTitle) =>
      _db.fetchLast7Days(habitTitle);

  @override
  Future<List<HabitEntry>> fetchMonthlyTotals(String habitTitle) =>
      _db.fetchMonthlyTotals(habitTitle);

  @override
  Future<void> clearEntries() => _db.clearEntries();

  @override
  Future<void> clearEntriesForHabit(String habitTitle) =>
      _db.clearEntriesForHabit(habitTitle);

  @override
  Future<List<HabitEntry>> fetchRange(String habitTitle, DateTime pivotDate) =>
      _db.fetchRange(habitTitle, pivotDate);

  @override
  Future<void> deleteDay(String habitTitle, DateTime date) =>
      _db.deleteDay(habitTitle, date);
}
