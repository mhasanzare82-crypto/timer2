import '../utils/jalali_date_storage.dart';

class TimeRecord {
  final int? id;
  final String title;
  final String category;
  final int durationSeconds;
  final DateTime createdAt;
  final DateTime activityDate;
  final String? note;

  const TimeRecord({
    this.id,
    required this.title,
    required this.category,
    required this.durationSeconds,
    required this.createdAt,
    required this.activityDate,
    this.note,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'category': category,
      'durationSeconds': durationSeconds,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'activityDate': activityDate.millisecondsSinceEpoch,
      'note': note,
    };
  }

  factory TimeRecord.fromMap(Map<String, Object?> map) {
    return TimeRecord(
      id: map['id'] as int?,
      title: map['title'] as String,
      category: map['category'] as String,
      durationSeconds: map['durationSeconds'] as int,
      createdAt: JalaliDateStorage.decode(map['createdAt']),
      activityDate: JalaliDateStorage.decode(map['activityDate']),
      note: map['note'] as String?,
    );
  }
}
