import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'habit.dart';
import 'habit_entry.dart';
import 'habits_repository.dart';
import 'sqflite_habits_repository.dart';
import 'db_helper.dart';
import 'sync_service.dart';
import 'interactive_trend_chart.dart';
import 'edit_habit_screen.dart';

final String userId = 'default_user';

class TrackHabitScreen extends StatefulWidget {
  const TrackHabitScreen({Key? key}) : super(key: key);

  @override
  State<TrackHabitScreen> createState() => _TrackHabitScreenState();
}

class _TrackHabitScreenState extends State<TrackHabitScreen> {
  final HabitsRepository _repo = SqfliteHabitsRepository();
  late List<Habit> _habits;

  DateTime _selectedDate = DateTime.now();
  String _selectedHabitTitle = '';

  // chart / table data
  List<String> _last7Labels = [];
  List<double> _last7Values = [];
  List<HabitEntry> _monthlyTotals = [];

  // pedometer
  StreamSubscription<StepCount>? _stepSub;
  int? _sensorPrev; // last raw StepCount from sensor
  int _runningTotal = 0; // what we show & store
  int? _lastSavedSteps; // last value written to DB

  // ---------------------------------------------------------------------------
  @override
  void initState() {
    super.initState();

    _habits = [
      Habit(
        title: 'Reduce Plastic',
        unit: 'kg',
        goal: 5,
        currentValue: 0,
        quickAdds: const [],
      ),
      Habit(
        title: 'Short Walk',
        unit: 'steps',
        goal: 10000,
        currentValue: 0,
        quickAdds: const [],
        usePedometer: true,
      ),
    ];
    _selectedHabitTitle = _habits.first.title;

    SyncService().start();
    _initSavedTotal().then((_) {
      _requestPermission();
      _startPedometer();
    });
    _loadAllData();
  }

  @override
  void dispose() {
    _stepSub?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // SQLite helper – read the latest Short‑Walk total for today
  // ---------------------------------------------------------------------------
  Future<void> _initSavedTotal() async {
    _runningTotal = await DbHelper().getLastSavedSteps() ?? 0;
    _lastSavedSteps = _runningTotal;
  }

  // ---------------------------------------------------------------------------
  // PERMISSION
  // ---------------------------------------------------------------------------
  Future<void> _requestPermission() async {
    final st = await Permission.activityRecognition.request();
    if (!st.isGranted && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Motion permission denied')));
    }
  }

  // ---------------------------------------------------------------------------
  // PEDOMETER LISTENER
  // ---------------------------------------------------------------------------
  void _startPedometer() {
    final stepIdx = _habits.indexWhere((h) => h.usePedometer);
    if (stepIdx == -1) return;

    _stepSub = Pedometer.stepCountStream.listen((event) async {
      final today = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );

      // ── A.  first event after launch → just remember raw value
      if (_sensorPrev == null) {
        _sensorPrev = event.steps;
        return;
      }

      // ── B.  delta = currentRaw – prevRaw  (sensor may reset to 0)
      int delta = event.steps - _sensorPrev!;
      if (delta < 0) delta = event.steps; // handle sensor reset
      _sensorPrev = event.steps;

      // ── C.  accumulate and update UI
      _runningTotal += delta;

      setState(() {
        final h = _habits[stepIdx];
        _habits[stepIdx] = h.copyWith(currentValue: _runningTotal.toDouble());
      });

      // ── D.  write every change
      if (_lastSavedSteps != _runningTotal) {
        _lastSavedSteps = _runningTotal;

        await DbHelper().saveSteps(_runningTotal);

        final entry = HabitEntry(
          id: const Uuid().v4(),
          habitTitle: 'Short Walk',
          date: today,
          value: _runningTotal.toDouble(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await _repo.deleteDay('Short Walk', today);
        await _repo.upsertEntry(entry); // SQLite + Firebase
        await _loadDataForSelectedHabit(_selectedHabitTitle);
      }
    }, onError: (e) => debugPrint('Pedometer error: $e'));
  }

  // ---------------------------------------------------------------------------
  // DATA LOADERS
  // ---------------------------------------------------------------------------
  Future<void> _loadAllData() async {
    await _updateCurrentValues();
    await _loadDataForSelectedHabit(_selectedHabitTitle);
  }

  Future<void> _updateCurrentValues() async {
    final key = DateFormat('yyyy-MM-dd').format(_selectedDate);
    for (var i = 0; i < _habits.length; i++) {
      final h = _habits[i];
      if (h.usePedometer) continue; // live updated

      final entries = await _repo.fetchRange(h.title, _selectedDate);
      final todayTotal = entries
          .where((e) => DateFormat('yyyy-MM-dd').format(e.date) == key)
          .fold<double>(0, (s, e) => s + e.value);
      setState(() => _habits[i] = h.copyWith(currentValue: todayTotal));
    }
  }

  Future<void> _loadDataForSelectedHabit(String habitTitle) async {
    final entries = await _repo.fetchRange(habitTitle, _selectedDate);
    final fmt = DateFormat('yyyy-MM-dd');

    final daily = <String, double>{};
    for (var i = 0; i < 7; i++) {
      final d = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      ).subtract(Duration(days: 6 - i));
      daily[fmt.format(d)] = 0;
    }
    for (final e in entries) {
      final k = fmt.format(e.date);
      if (daily.containsKey(k)) daily[k] = daily[k]! + e.value;
    }
    final monthly = await _repo.fetchMonthlyTotals(habitTitle);
    setState(() {
      _last7Labels = daily.keys.toList();
      _last7Values = daily.values.toList();
      _monthlyTotals = monthly;
    });
  }

  // ---------------------------------------------------------------------------
  // UI HELPERS
  // ---------------------------------------------------------------------------
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      await _loadAllData();
    }
  }

  Future<void> _showAddHabitDialog() async {
    final titleCtrl = TextEditingController();
    final unitCtrl = TextEditingController(text: 'kg');
    final goalCtrl = TextEditingController(text: '5');

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Create Habit'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                TextField(
                  controller: unitCtrl,
                  decoration: const InputDecoration(labelText: 'Unit'),
                ),
                TextField(
                  controller: goalCtrl,
                  decoration: const InputDecoration(labelText: 'Goal'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Add'),
              ),
            ],
          ),
    );

    if (ok == true && titleCtrl.text.trim().isNotEmpty) {
      setState(() {
        _habits.add(
          Habit(
            title: titleCtrl.text.trim(),
            unit: unitCtrl.text.trim(),
            goal: double.tryParse(goalCtrl.text) ?? 0,
            currentValue: 0,
            quickAdds: const [],
          ),
        );
      });
    }
  }

  Future<void> _clearAll() async {
    await DbHelper().deleteAllEntries();
    await _loadAllData();
  }

  // ---------------------------------------------------------------------------
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
            onPressed: _pickDate,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: _clearAll,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Date: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),

            for (var i = 0; i < _habits.length; i++) ...[
              _buildHabitCard(i, theme),
              const SizedBox(height: 16),
            ],

            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Last 7 Days', style: theme.textTheme.titleLarge),
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
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _selectedHabitTitle = v);
                      _loadDataForSelectedHabit(v);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
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
            const SizedBox(height: 8),
            ..._monthlyTotals.map(
              (e) => Text(
                '${DateFormat('MMMM yyyy').format(e.date)}: ${e.value.toStringAsFixed(1)}',
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        tooltip: 'New Habit',
        onPressed: _showAddHabitDialog,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  Widget _buildHabitCard(int index, ThemeData theme) {
    final h = _habits[index];
    final progress =
        h.goal == 0 ? 0.0 : (h.currentValue / h.goal).clamp(0.0, 1.0);

    return Card(
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
                  onPressed:
                      h.usePedometer
                          ? null
                          : () async {
                            final todayEntries = await _repo.fetchRange(
                              h.title,
                              _selectedDate,
                            );
                            final key = DateFormat(
                              'yyyy-MM-dd',
                            ).format(_selectedDate);

                            HabitEntry? existing;
                            try {
                              existing = todayEntries.firstWhere(
                                (e) =>
                                    DateFormat('yyyy-MM-dd').format(e.date) ==
                                    key,
                              );
                            } catch (_) {
                              existing = null; // 今天还没有条目
                            }
                            final result =
                                await Navigator.push<Map<String, dynamic>>(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (_) => EditHabitScreen(
                                          habit: h,
                                          existingEntry: existing,
                                          initialDate: _selectedDate,
                                        ),
                                  ),
                                );
                            if (result != null) {
                              final updated = result['habit'] as Habit;
                              final entry = result['entry'] as HabitEntry?;
                              if (entry != null) {
                                await _repo.deleteDay(
                                  entry.habitTitle,
                                  entry.date,
                                );
                                await _repo.upsertEntry(entry);
                              }
                              setState(() => _habits[index] = updated);
                              await _loadAllData();
                            }
                          },
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 4),
            Text('${h.currentValue.toStringAsFixed(2)}/${h.goal} ${h.unit}'),
          ],
        ),
      ),
    );
  }
}
