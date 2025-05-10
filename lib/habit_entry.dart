import 'package:cloud_firestore/cloud_firestore.dart';

class HabitEntry {
  final String id;
  final String user_email;
  final String habitTitle;
  final DateTime date;
  final double value;
  final DateTime createdAt;
  final DateTime updatedAt;

  HabitEntry({
    required this.id,
    required this.user_email,
    required this.habitTitle,
    required this.date,
    required this.value,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_email': user_email,
    'habitTitle': habitTitle,
    'date': Timestamp.fromDate(date),
    'value': value,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  Map<String, Object?> toMap() => {
    'id'         : id,
    'user_email' : user_email,
    'habitTitle' : habitTitle,
    'date'       : date.toIso8601String(),
    'value'      : value,
    'createdAt'  : createdAt.toIso8601String(),
    'updatedAt'  : updatedAt.toIso8601String(),
  };

  factory HabitEntry.fromJson(Map<String, dynamic> json) => HabitEntry(
    id: json['id'] as String,
    user_email: json['user_email'] as String,
    habitTitle: json['habitTitle'] as String,
    date: (json['date'] as Timestamp).toDate(),
    value: (json['value'] as num).toDouble(),
    createdAt: (json['createdAt'] as Timestamp).toDate(),
    updatedAt: (json['updatedAt'] as Timestamp).toDate(),
  );
}