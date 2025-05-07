import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'habits_repository.dart';
import 'sqflite_habits_repository.dart';
import 'db_helper.dart';
import 'habit.dart';
import 'habit_entry.dart';
import 'sync_service.dart';
import 'interactive_trend_chart.dart';
import 'edit_habit_screen.dart';
import 'package:uuid/uuid.dart';

class TrackHabitScreen extends StatefulWidget {
  const TrackHabitScreen({Key? key}) : super(key: key);

  @override
  State<TrackHabitScreen> createState() => _TrackHabitScreenState();
}

class _TrackHabitScreenState extends State<TrackHabitScreen> {
  final HabitsRepository _repo = SqfliteHabitsRepository();
  List<Habit> _habits = [
    Habit(
      title: 'Reduce Plastic',
      unit: 'kg',
      goal: 5.0,
      currentValue: 0.0,
      quickAdds: [0.1, 0.5, 1.0],
    ),
    Habit(
      title: 'Short Walk',
      unit: 'km',
      goal: 20.0,
      currentValue: 0.0,
      quickAdds: [0.5, 1.0, 2.0],
    ),
  ];
  String _selectedHabitTitle = '';
  List<double> _last7Values = [];
  List<String> _last7Labels = [];
  List<HabitEntry> _monthlyTotals = [];
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _selectedHabitTitle = _habits.first.title;
    SyncService().start();
    _loadAllData();
  }

  Future<void> _pickGlobalDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: today.subtract(const Duration(days: 365)),
      // 想多远自己设
      lastDate: today,
      helpText: 'Choose Date',
      confirmText: 'Confirm',
      cancelText: 'Cancel',
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      await _loadAllData();
    }
  }

  Future<void> _loadAllData() async {
    await _updateCurrentValues();
    await _loadDataForSelectedHabit(_selectedHabitTitle);
  }

  Future<void> _loadDataForSelectedHabit(String habitTitle) async {
    final entries = await _repo.fetchRange(habitTitle, _selectedDate);
    final now = _selectedDate;
    final dailyMap = <String, double>{};
    for (var i = 0; i < 7; i++) {
      final day = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: 6 - i));
      final key = DateFormat('yyyy-MM-dd').format(day);
      dailyMap[key] = 0.0;
    }
    for (final e in entries) {
      final key = DateFormat('yyyy-MM-dd').format(e.date);
      if (dailyMap.containsKey(key)) dailyMap[key] = dailyMap[key]! + e.value;
    }
    final monthlyEntries = await _repo.fetchMonthlyTotals(habitTitle);
    setState(() {
      _last7Labels = dailyMap.keys.toList();
      _last7Values = dailyMap.values.toList();
      _monthlyTotals = monthlyEntries;
    });
  }

  Future<void> _updateCurrentValues() async {
    final dayKey = DateFormat('yyyy-MM-dd').format(_selectedDate);

    for (var i = 0; i < _habits.length; i++) {
      final h = _habits[i];

      // weekEntries still returns the 7‑day window
      final weekEntries = await _repo.fetchRange(h.title, _selectedDate);

      // keep ONLY rows whose date == _selectedDate
      final todayTotal = weekEntries
          .where((e) =>
      DateFormat('yyyy-MM-dd').format(e.date) == dayKey)
          .fold<double>(0, (sum, e) => sum + e.value);

      setState(() {
        _habits[i] = Habit(
          title:        h.title,
          unit:         h.unit,
          goal:         h.goal,
          currentValue: todayTotal,   // ← now just that one day
          quickAdds:    h.quickAdds,
        );
      });
    }
  }

  Future<void> _clearEntries() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Confirm Delete'),
            content: const Text('Are you sure you want to delete all entries?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirm'),
              ),
            ],
          ),
    );
    if (confirm == true) {
      await DbHelper().dropAndRecreateEntriesTable();
      await _loadAllData();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('All entries cleared')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Habit Tracking'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Choose Date',
            onPressed: _pickGlobalDate,
          ),
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            tooltip: 'Sync to Firebase',
            onPressed: () async {
              await SyncService().pushAllEntries();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Synced local entries to Firebase'),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Reset Database',
            onPressed: () async {
              await DbHelper().dropAndRecreateEntriesTable();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Database file deleted')),
              );
              await _loadAllData();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Record Date：${DateFormat('yyyy-MM-dd').format(_selectedDate)}',
              style: theme.textTheme.labelLarge,
            ),
            Text('Weekly Habits', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            for (var i = 0; i < _habits.length; i++) ...[
              _buildHabitCard(i, theme),
              const SizedBox(height: 16),
            ],

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Last 7 Days Trend', style: theme.textTheme.titleLarge),
                DropdownButton<String>(
                  value: _selectedHabitTitle,
                  items:
                      _habits
                          .map(
                            (h) => DropdownMenuItem(
                              value: h.title,
                              child: Text(h.title),
                            ),
                          )
                          .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedHabitTitle = value);
                      _loadDataForSelectedHabit(value);
                    }
                  },
                ),
              ],
            ),

            const SizedBox(height: 12),
            InteractiveTrendChart(
              values: _last7Values,
              labels: _last7Labels,
              maxY:
                  _habits
                      .firstWhere((h) => h.title == _selectedHabitTitle)
                      .goal,
            ),

            const SizedBox(height: 24),
            Text('Monthly Totals', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            ..._monthlyTotals.map(
              (e) => Text(
                '${DateFormat('MMMM yyyy').format(e.date)}: ${e.value.toStringAsFixed(1)} ${e.habitTitle}',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHabitCard(int index, ThemeData theme) {
    final h = _habits[index];
    final progress =
        h.goal == 0 ? 0.0 : (h.currentValue / h.goal).clamp(0.0, 1.0);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(h.title, style: theme.textTheme.titleMedium),
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () async {
                    // 1) load any existing entry for this habit on _selectedDate
                    final todayEntries = await _repo.fetchRange(
                      h.title,
                      _selectedDate,
                    ); // uses fetchRange(habitTitle, pivotDate) :contentReference[oaicite:0]{index=0}:contentReference[oaicite:1]{index=1}
                    final existing = todayEntries.isNotEmpty ? todayEntries.first : null;

                    // 2) push the editor, passing both habit & existing entry
                    final result =
                    await Navigator.push<Map<String, dynamic>>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EditHabitScreen(
                          habit: h,
                          existingEntry: existing,
                          initialDate: _selectedDate,
                        ),
                      ),
                    );

                    if (result != null) {
                      // 3) pull back the updated Habit and the new/updated entry
                      final updatedHabit = result['habit'] as Habit;
                      final entry       = result['entry'] as HabitEntry?;

                      // 4) if entry != null, upsert it (this will replace same-ID row)
                      if (entry != null) {
                        await _repo.deleteDay(entry.habitTitle, entry.date);  // ← use entry.date
                        await _repo.upsertEntry(entry);
                      }

                      setState(() => _habits[index] = updatedHabit);
                      await _loadAllData();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            Text('${h.currentValue.toStringAsFixed(1)}/${h.goal} ${h.unit}'),
          ],
        ),
      ),
    );
  }
}
