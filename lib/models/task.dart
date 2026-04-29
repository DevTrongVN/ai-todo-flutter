class Task {
  int id;
  String title;
  String? description;
  DateTime dueDate;
  bool isCompleted;
  int? remindBeforeMins;
  String repeatMode;
  List<int>? repeatDays;

  Task({
    required this.id,
    required this.title,
    this.description,
    required this.dueDate,
    this.isCompleted = false,
    this.remindBeforeMins,
    this.repeatMode = 'NONE',
    this.repeatDays,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'datetime': dueDate.toIso8601String(),
      'isCompleted': isCompleted ? 1 : 0,
      'remindBeforeMins': remindBeforeMins,
      'repeatMode': repeatMode,
      'repeatDays': repeatDays?.join(','),
    };
  }

  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      id: map['id'],
      title: map['title'],
      description: map['description'],
      dueDate: DateTime.parse(map['datetime']),
      isCompleted: map['isCompleted'] == 1,
      remindBeforeMins: map['remindBeforeMins'],
      repeatMode: map['repeatMode'] ?? 'NONE',
      repeatDays: map['repeatDays'] != null
          ? map['repeatDays'].toString().split(',').map(int.parse).toList()
          : null,
    );
  }
}