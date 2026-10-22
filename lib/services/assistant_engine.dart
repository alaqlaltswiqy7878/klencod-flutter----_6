import 'package:shared_preferences/shared_preferences.dart';
import '../models/task_item.dart';
import '../services/task_store.dart';

class AssistantEngine {
  static Future<String> reply(String query) async {
    final text = query.trim().toLowerCase();
    final tasks = TaskStore.getAllTasks();
    final now = DateTime.now();
    if (text.contains('مرحبا') || text.contains('السلام') || text.contains('اهلا')) {
      return 'أهلاً بك. أنا جاهز لمساعدتك في تنظيم يومك.';
    }
    if (text.contains('الان') || text.contains('الآن') || text.contains('ماذا افعل')) {
      final active = tasks.where((t) => t.isActiveAt(now)).toList();
      if (active.isNotEmpty) return 'مهمتك الحالية هي: ${active.first.title}، وتنتهي الساعة ${formatHm(active.first.endOn(now))}.';
      return 'لا توجد مهمة جارية الآن.';
    }
    if (text.contains('القادمة') || text.contains('التالية')) {
      TaskItem? best;
      DateTime? when;
      for (final task in tasks) {
        final next = task.nextOccurrenceAfter(now);
        if (next != null && (when == null || next.isBefore(when!))) { best = task; when = next; }
      }
      return best == null ? 'لا توجد مهام قادمة.' : 'مهمتك القادمة هي ${best.title} الساعة ${formatHm(when!)}.';
    }
    if (text.contains('مهام') || text.contains('عدد') || text.contains('اليوم')) {
      final today = tasks.where((t) => t.occursOn(now)).toList();
      final done = today.where((t) => t.isDoneOn(now)).length;
      return 'لديك ${today.length} مهام اليوم، أنجزت منها $done.';
    }
    return 'أستطيع إخبارك بمهمتك الحالية أو القادمة وعدد مهام اليوم. ولإضافة مهمة استخدم شاشة المساعد الكاملة.';
  }

  static Future<void> saveExchange(String question, String answer) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('quwat_last_assistant_exchange', '$question\n$answer');
  }
}
