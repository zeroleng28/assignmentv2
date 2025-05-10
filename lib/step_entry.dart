import 'package:intl/intl.dart';

class StepEntry {
  final String id;
  final String user_email;
  final DateTime day;
  final double count;
  final DateTime createdAt;
  final DateTime updatedAt;

  StepEntry({
    required this.id,
    required this.user_email,
    required this.day,
    required this.count,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, Object?> toMap() => {
    'id'       : id,
    'user_email': user_email,
    'day'      : DateFormat('yyyy-MM-dd').format(day),
    'count'    : count,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory StepEntry.fromMap(Map<String, Object?> m) => StepEntry(
    id       : m['id'] as String,
    user_email:    m['user_email'] as String,
    day      : DateTime.parse(m['day'] as String),
    count    : (m['count'] as num).toDouble(),
    createdAt: DateTime.parse(m['createdAt'] as String),
    updatedAt: DateTime.parse(m['updatedAt'] as String),
  );
}
