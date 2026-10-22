import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task_item.dart';

class TaskStore {
  static const String _key = 'quwat_alaan_tasks_data';
  static SharedPreferences? _prefs;
  static List<TaskItem> _tasks = [];

  /// يزداد عند أي تغيير ليحدّث الواجهات المستمعة.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _load();
  }

  /// إعادة القراءة من القرص (مثلاً بعد تعديل من الخلفية).
  static Future<void> reload() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs?.reload();
    _load();
    changes.value++;
  }

  static void _load() {
    final raw = _prefs?.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(raw);
        _tasks = decoded.map((e) => TaskItem.fromMap(Map<String, dynamic>.from(e))).toList();
      } catch (_) {
        _tasks = [];
      }
    } else {
      _tasks = [];
    }
  }

  static List<TaskItem> getAllTasks() {
    return List.unmodifiable(_tasks);
  }

  static TaskItem? getById(String id) {
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// يعيد المهمة المتداخلة، إن وجدت، عبر أول يوم مشترك بينهما.
  static TaskItem? findOverlap(TaskItem candidate) {
    final firstDay = DateTime(candidate.startTime.year, candidate.startTime.month, candidate.startTime.day);
    final daysToCheck = candidate.isRecurring ? 370 : 1;
    for (var offset = 0; offset < daysToCheck; offset++) {
      final day = firstDay.add(Duration(days: offset));
      if (!candidate.occursOn(day)) continue;
      final candidateStart = candidate.startOn(day);
      final candidateEnd = candidate.endOn(day);
      for (final other in _tasks) {
        if (other.id == candidate.id || !other.occursOn(day)) continue;
        final otherStart = other.startOn(day);
        final otherEnd = other.endOn(day);
        if (candidateStart.isBefore(otherEnd) && otherStart.isBefore(candidateEnd)) {
          return other;
        }
      }
    }
    return null;
  }

  static TaskItem? findOverlapAt(TaskItem candidate, DateTime start, DateTime end) {
    for (final other in _tasks) {
      if (other.id == candidate.id || !other.occursOn(start)) continue;
      final otherStart = other.startOn(start);
      final otherEnd = other.endOn(start);
      if (start.isBefore(otherEnd) && otherStart.isBefore(end)) return other;
    }
    return null;
  }

  static Future<void> saveTask(TaskItem task) async {
    final index = _tasks.indexWhere((t) => t.id == task.id);
    if (index >= 0) {
      _tasks[index] = task;
    } else {
      _tasks.add(task);
    }
    await _persist();
    changes.value++;
  }

  static Future<void> deleteTask(String id) async {
    _tasks.removeWhere((t) => t.id == id);
    await _persist();
    changes.value++;
  }

  /// تعليم المهمة كمنجزة في اليوم المحدد (تُستخدم من زر الإشعار).
  static Future<bool> markDone(String id, DateTime day) async {
    final task = getById(id);
    if (task == null) return false;
    task.setDoneOn(day, true);
    await saveTask(task);
    return true;
  }

  static Future<void> _persist() async {
    _prefs ??= await SharedPreferences.getInstance();
    final data = jsonEncode(_tasks.map((t) => t.toMap()).toList());
    await _prefs?.setString(_key, data);
  }
}
