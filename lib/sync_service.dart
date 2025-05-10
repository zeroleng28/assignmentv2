import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:uuid/uuid.dart';
import 'db_helper.dart';
import 'habit_entry.dart';
import 'main.dart';
import 'package:flutter/material.dart';

void _showStatus(String message) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final ctx = navigatorKey.currentContext;
    if (ctx != null) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(message)));
    }
  });
}

class SyncService {
  static final SyncService _instance = SyncService._();

  factory SyncService() => _instance;

  SyncService._();

  final _dbHelper = DbHelper();
  final _firestore = FirebaseFirestore.instance;
  final _connectivity = Connectivity();

  Future<void> deleteEntriesForHabit(String habitTitle) async {
    await _dbHelper.clearEntriesForHabit(habitTitle);

    final snapshot =
        await _firestore
            .collection('entries')
            .where('habitTitle', isEqualTo: habitTitle)
            .get();

    for (final doc in snapshot.docs) {
      await doc.reference.delete();
    }
  }

  Future<void> pushAllEntries() async {
    final database = await _dbHelper.database;
    final rows = await database.query('entries');
    for (final r in rows) {
      final entry = HabitEntry(
        id: r['id'] as String,
        user_email: r['user_email'] as String,
        habitTitle: r['habitTitle'] as String,
        date: DateTime.parse(r['date'] as String),
        value: (r['value'] as num).toDouble(),
        createdAt: DateTime.parse(r['createdAt'] as String),
        updatedAt: DateTime.parse(r['updatedAt'] as String),
      );
      await _firestore
          .collection('entries')
          .doc(entry.id)
          .set(entry.toJson(), SetOptions(merge: true));
    }
  }

  void start() {
    Future<void> _pushAllEntries() async {
      // ① use the 'database' getter
      final database = await _dbHelper.database;
      final rows = await database.query('entries');
      for (final r in rows) {
        // ② parse ISO-8601 strings back to DateTime
        final entry = HabitEntry(
          id: r['id'] as String,
          user_email: r['user_email'] as String,
          habitTitle: r['habitTitle'] as String,
          date: DateTime.parse(r['date'] as String),
          value: (r['value'] as num).toDouble(),
          createdAt: DateTime.parse(r['createdAt'] as String),
          updatedAt: DateTime.parse(r['updatedAt'] as String),
        );
        await _firestore
            .collection('entries')
            .doc(entry.id)
            .set(entry.toJson(), SetOptions(merge: true));
      }
    }

    /// Pull every document from Firestore and upsert it into SQLite
    Future<void> _pullRemoteEntries() async {
      final snapshot = await _firestore.collection('entries').get();
      for (final doc in snapshot.docs) {
        final data = doc.data();

        final entry = HabitEntry(
          id: doc.id,
          user_email: data['user_email'] as String? ?? 'Unknown',
          habitTitle: data['habitTitle'] as String? ?? 'Unknown Habit',
          date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
          value: (data['value'] as num?)?.toDouble() ?? 0.0,
          createdAt:
              (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          updatedAt:
              (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        );

        await _dbHelper.upsertEntry(entry);
      }
    }

    _connectivity.onConnectivityChanged.listen((status) {
      if (status == ConnectivityResult.none) {
        _showStatus('Offline mode');
      } else {
        _showStatus('Syncing...');
        _pushAllEntries();
        _pullRemoteEntries();
      }
    });

    /// Helper to create a new entry with UUID and timestamps
    HabitEntry createEntry(String user_email, String habitTitle, DateTime date, double value) {
      final now = DateTime.now();
      return HabitEntry(
        id: const Uuid().v4(),
        user_email: user_email,
        habitTitle: habitTitle,
        date: date,
        value: value,
        createdAt: now,
        updatedAt: now,
      );
    }
  }

  Future<void> pushEntry(HabitEntry entry) async {
    try {
      await _firestore
          .collection('entries')
          .doc(entry.id)
          .set(entry.toJson(), SetOptions(merge: true));
    } catch (_) {}
  }
}
