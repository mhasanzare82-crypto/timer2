class TimeRecord {
  final int? id;
  final String title;
  final String category;
  final int durationSeconds;
  final DateTime createdAt;
  final DateTime activityDate;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String? note;

  const TimeRecord({
    this.id,
    required this.title,
    required this.category,
    required this.durationSeconds,
    required this.createdAt,
    required this.activityDate,
    this.startedAt,
    this.endedAt,
    this.note,
  });

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'category': category,
    'durationSeconds': durationSeconds,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'activityDate': activityDate.millisecondsSinceEpoch,
    'startedAt': startedAt?.millisecondsSinceEpoch,
    'endedAt': endedAt?.millisecondsSinceEpoch,
    'note': note,
  };

  factory TimeRecord.fromMap(Map<String, Object?> map) => TimeRecord(
    id: map['id'] as int?,
    title: map['title'] as String,
    category: map['category'] as String,
    durationSeconds: (map['durationSeconds'] as num).toInt(),
    createdAt: DateTime.fromMillisecondsSinceEpoch((map['createdAt'] as num).toInt()),
    activityDate: DateTime.fromMillisecondsSinceEpoch((map['activityDate'] as num).toInt()),
    startedAt: map['startedAt'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((map['startedAt'] as num).toInt()),
    endedAt: map['endedAt'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((map['endedAt'] as num).toInt()),
    note: map['note'] as String?,
  );
}
