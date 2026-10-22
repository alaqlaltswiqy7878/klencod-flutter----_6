import 'sub_task.dart';

enum Recurrence { none, daily, weekly }

/// أيام الأسبوع بترتيب العرض (DateTime.weekday: 1=الإثنين ... 7=الأحد)
const List<int> kWeekdayOrder = [7, 1, 2, 3, 4, 5, 6];

const Map<int, String> kWeekdayNames = {
  7: 'الأحد',
  1: 'الإثنين',
  2: 'الثلاثاء',
  3: 'الأربعاء',
  4: 'الخميس',
  5: 'الجمعة',
  6: 'السبت',
};

String formatHm(DateTime dt) {
  return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

String formatYmd(DateTime dt) {
  return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
}

class TaskItem {
  final String id;
  String title;
  String description;
  DateTime startTime;
  DateTime endTime;
  bool isCompleted;
  String category;
  String priority;
  Recurrence recurrence;
  List<int> weekdays;
  List<SubTask> subTasks;
  List<String> completedDates;
  List<String> snoozedDates;

  TaskItem({
    required this.id,
    required this.title,
    this.description = '',
    required this.startTime,
    required this.endTime,
    this.isCompleted = false,
    this.category = 'عام',
    this.priority = 'متوسطة',
    this.recurrence = Recurrence.none,
    List<int>? weekdays,
    List<SubTask>? subTasks,
    List<String>? completedDates,
    List<String>? snoozedDates,
  })  : weekdays = weekdays ?? <int>[],
        subTasks = subTasks ?? <SubTask>[],
        completedDates = completedDates ?? <String>[],
        snoozedDates = snoozedDates ?? <String>[];

  static String dateKey(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  bool get isRecurring => recurrence != Recurrence.none;

  Duration get duration => endTime.difference(startTime);

  String get recurrenceLabel {
    switch (recurrence) {
      case Recurrence.none:
        return '';
      case Recurrence.daily:
        return 'يتكرر يومياً';
      case Recurrence.weekly:
        final names = kWeekdayOrder
            .where((d) => weekdays.contains(d))
            .map((d) => kWeekdayNames[d]!)
            .join('، ');
        return 'يتكرر: $names';
    }
  }

  /// هل تقع المهمة في اليوم المحدد؟
  bool occursOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final startDay = DateTime(startTime.year, startTime.month, startTime.day);
    switch (recurrence) {
      case Recurrence.none:
        return d.isAtSameMomentAs(startDay);
      case Recurrence.daily:
        return !d.isBefore(startDay);
      case Recurrence.weekly:
        return !d.isBefore(startDay) && weekdays.contains(d.weekday);
    }
  }

  DateTime startOn(DateTime day) {
    return DateTime(day.year, day.month, day.day, startTime.hour, startTime.minute);
  }

  DateTime endOn(DateTime day) {
    return startOn(day).add(duration);
  }

  bool isDoneOn(DateTime day) {
    if (isRecurring) return completedDates.contains(dateKey(day));
    return isCompleted;
  }

  bool isSnoozedOn(DateTime day) => snoozedDates.contains(dateKey(day));

  void setDoneOn(DateTime day, bool value) {
    if (isRecurring) {
      final key = dateKey(day);
      completedDates.remove(key);
      if (value) completedDates.add(key);
    } else {
      isCompleted = value;
    }
  }

  bool isActiveAt(DateTime now) {
    if (!occursOn(now) || isDoneOn(now)) return false;
    return startOn(now).isBefore(now) && endOn(now).isAfter(now);
  }

  /// موعد البدء القادم (غير المنجز) بعد الوقت المحدد
  DateTime? nextOccurrenceAfter(DateTime now) {
    for (var i = 0; i <= 7; i++) {
      final day = DateTime(now.year, now.month, now.day + i);
      if (!occursOn(day) || isDoneOn(day)) continue;
      final s = startOn(day);
      if (s.isAfter(now)) return s;
    }
    return null;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'isCompleted': isCompleted ? 1 : 0,
      'category': category,
      'priority': priority,
      'recurrence': recurrence.index,
      'weekdays': weekdays,
      'subTasks': subTasks.map((s) => s.toMap()).toList(),
      'completedDates': completedDates,
      'snoozedDates': snoozedDates,
    };
  }

  factory TaskItem.fromMap(Map<String, dynamic> map) {
    final completed = map['isCompleted'];
    final recurrenceValue = map['recurrence'];
    return TaskItem(
      id: map['id'] as String,
      title: (map['title'] as String?) ?? 'مهمة بلا عنوان',
      description: (map['description'] as String?) ?? '',
      startTime: DateTime.parse(map['startTime'] as String),
      endTime: DateTime.parse(map['endTime'] as String),
      isCompleted: completed == true || completed == 1,
      category: (map['category'] as String?) ?? 'عام',
      priority: (map['priority'] as String?) ?? 'متوسطة',
      recurrence: Recurrence.values[(((recurrenceValue is int) ? recurrenceValue : int.tryParse('$recurrenceValue') ?? 0).clamp(0, 2)).toInt()],
      weekdays: ((map['weekdays'] as List?) ?? const []).map((e) => e is int ? e : int.tryParse('$e') ?? 0).where((e) => e > 0).toList(),
      subTasks: ((map['subTasks'] as List?) ?? const [])
          .map((e) => SubTask.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      completedDates: ((map['completedDates'] as List?) ?? const []).map((e) => e as String).toList(),
      snoozedDates: ((map['snoozedDates'] as List?) ?? const []).map((e) => e as String).toList(),
    );
  }
}
