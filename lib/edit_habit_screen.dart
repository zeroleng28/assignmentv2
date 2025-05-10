import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'habit.dart';
import 'habit_entry.dart';

class EditHabitScreen extends StatefulWidget {
  final Habit habit;
  final HabitEntry? existingEntry;
  final DateTime initialDate;

  const EditHabitScreen({
    Key? key,
    required this.habit,
    this.existingEntry,
    required this.initialDate,
  }) : super(key: key);

  @override
  State<EditHabitScreen> createState() => _EditHabitScreenState();
}

class _EditHabitScreenState extends State<EditHabitScreen> {
  late TextEditingController _titleCtrl;
  late TextEditingController _unitCtrl;
  late TextEditingController _goalCtrl;
  late TextEditingController _currentValueCtrl;

  late double _currentValue;
  late DateTime _entryDate;

  @override
  void initState() {
    super.initState();
    _entryDate = widget.existingEntry?.date ?? widget.initialDate;
    _titleCtrl = TextEditingController(text: widget.habit.title);
    _unitCtrl = TextEditingController(text: widget.habit.unit);
    _goalCtrl = TextEditingController(text: widget.habit.goal.toString());

    _currentValue = widget.existingEntry?.value ?? widget.habit.currentValue;
    _currentValueCtrl = TextEditingController(
      text: _currentValue.toStringAsFixed(1),
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _unitCtrl.dispose();
    _goalCtrl.dispose();
    _currentValueCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _entryDate,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _entryDate = picked);
    }
  }

  void _save() {
    final title = _titleCtrl.text.trim();
    final unit = _unitCtrl.text.trim();
    final goal = double.tryParse(_goalCtrl.text) ?? widget.habit.goal;

    final inputValue = double.tryParse(_currentValueCtrl.text) ?? 0.0;
    final clampedValue = inputValue.clamp(0.0, goal);

    final updatedHabit = Habit(
      title: title,
      unit: unit,
      goal: goal,
      currentValue: clampedValue,
      quickAdds: widget.habit.quickAdds,
    );

    final existing = widget.existingEntry;
    final sameDay =
        existing != null &&
        DateFormat('yyyy-MM-dd').format(existing.date) ==
            DateFormat('yyyy-MM-dd').format(_entryDate);

    final id = sameDay ? existing!.id : const Uuid().v4();
    final createdAt = sameDay ? existing!.createdAt : DateTime.now();
    final updatedAt = DateTime.now();

    final entry = HabitEntry(
      id: id,
      user_email: 'alice@example.com',
      habitTitle: title,
      date: DateTime(_entryDate.year, _entryDate.month, _entryDate.day),
      value: clampedValue,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

    Navigator.of(context).pop({'habit': updatedHabit, 'entry': entry});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Habit'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Save',
            onPressed: _save,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Habit Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _unitCtrl,
              decoration: const InputDecoration(labelText: 'Unit (e.g. kg)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _goalCtrl,
              decoration: const InputDecoration(labelText: 'Goal'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (v) {
                final g = double.tryParse(v) ?? widget.habit.goal;
                setState(() {
                  if (_currentValue > g) {
                    _currentValue = g;
                    _currentValueCtrl.text = g.toStringAsFixed(1);
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _currentValueCtrl,
              decoration: InputDecoration(
                labelText: 'Current Value',
                suffixText: _unitCtrl.text,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (v) {
                setState(() {
                  _currentValue = double.tryParse(v) ?? _currentValue;
                });
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Entry Date:'),
                const SizedBox(width: 8),
                Text(DateFormat('yyyy-MM-dd').format(_entryDate)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.calendar_today),
                  tooltip: 'Pick date',
                  onPressed: _pickDate,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Adjust with slider:'),
                Expanded(
                  child: Slider(
                    value: _currentValue,
                    min: 0,
                    max: double.tryParse(_goalCtrl.text) ?? widget.habit.goal,
                    divisions:
                        ((double.tryParse(_goalCtrl.text) ??
                                    widget.habit.goal) *
                                10)
                            .toInt(),
                    label: _currentValue.toStringAsFixed(1),
                    onChanged: (v) {
                      setState(() {
                        _currentValue = v;
                        _currentValueCtrl.text = v.toStringAsFixed(1);
                      });
                    },
                  ),
                ),
              ],
            ),
            Text(
              '${_currentValue.toStringAsFixed(1)} ${_unitCtrl.text}',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
