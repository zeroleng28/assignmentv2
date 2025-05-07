import 'habit_entry.dart';

abstract class HabitsRepository {
  Future<void> upsertEntry(HabitEntry entry);
  Future<List<HabitEntry>> fetchLast7Days(String habitTitle);
  Future<List<HabitEntry>> fetchMonthlyTotals(String habitTitle);
  Future<void> clearEntries();
  Future<void> clearEntriesForHabit(String habitTitle);
  Future<List<HabitEntry>> fetchRange(String habitTitle, DateTime pivotDate);
  Future<void> deleteDay(String habitTitle, DateTime date);
}