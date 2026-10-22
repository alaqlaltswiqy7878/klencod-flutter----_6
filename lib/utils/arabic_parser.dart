import '../models/task_item.dart';

class RecurrenceChoice {
  final Recurrence recurrence;
  final List<int> weekdays;
  RecurrenceChoice(this.recurrence, this.weekdays);
}

/// أدوات بسيطة لفهم الأوقات والمدد المكتوبة بالعربية.
class ArabicParser {
  static String normalize(String s) {
    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    var out = s.trim();
    for (var i = 0; i < 10; i++) {
      out = out.replaceAll(arabicDigits[i], '$i');
    }
    out = out
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll('٫', '.')
        .replaceAll('،', ',');
    return out.toLowerCase();
  }

  static bool looksLikeDuration(String raw) {
    final n = normalize(raw);
    if (n.contains('دقيق') || n.contains('دقايق')) return true;
    if (RegExp(r'ساعه|ساعتين|ساعات|ساعتان').hasMatch(n) && !n.contains('الساعه') && !n.contains(':')) {
      return true;
    }
    return false;
  }

  static Duration? parseDuration(String raw) {
    final n = normalize(raw);
    var minutes = 0;
    var ok = false;

    if (RegExp(r'نص(ف)?\s*ساعه').hasMatch(n)) {
      minutes = 30;
      ok = true;
    } else if (RegExp(r'ربع\s*ساعه').hasMatch(n)) {
      minutes = 15;
      ok = true;
    } else if (n.contains('ساعتين') || n.contains('ساعتان')) {
      minutes = 120;
      ok = true;
    } else {
      final h = RegExp(r'(\d+(?:\.\d+)?)\s*ساع').firstMatch(n);
      if (h != null) {
        minutes = (double.parse(h.group(1)!) * 60).round();
        ok = true;
      } else if (n.contains('ساعه') || n.contains('ساعات')) {
        minutes = 60;
        ok = true;
      }
      if (ok && n.contains('ونص')) minutes += 30;
    }

    final m = RegExp(r'(\d+)\s*د(?:قيق|قايق)').firstMatch(n);
    if (m != null) {
      minutes += int.parse(m.group(1)!);
      ok = true;
    }

    if (!ok || minutes <= 0) return null;
    return Duration(minutes: minutes);
  }

  /// يحوّل نصاً مثل "5 مساءً" أو "17:30" أو "بعد ساعة" إلى وقت.
  /// [base] يحدد اليوم المستخدم (ويُستخدم كـ"الآن" عند "بعد ...").
  static DateTime? parseTime(String raw, DateTime base) {
    final n = normalize(raw);

    if (n.contains('بعد غد') || n.contains('بعدغد')) {
      return DateTime(base.year, base.month, base.day + 2, base.hour, base.minute);
    }
    const weekdayNames = {
      'احد': 7, 'اثنين': 1, 'ثلاثاء': 2, 'اربعاء': 3,
      'خميس': 4, 'جمعه': 5, 'سبت': 6,
    };
    for (final entry in weekdayNames.entries) {
      if (n.contains(entry.key) && (n.contains('القادم') || n.contains('الجاي'))) {
        var day = DateTime(base.year, base.month, base.day);
        while (day.weekday != entry.value || !day.isAfter(DateTime(base.year, base.month, base.day))) {
          day = day.add(const Duration(days: 1));
        }
        return DateTime(day.year, day.month, day.day, base.hour, base.minute);
      }
    }

    if (n.contains('بعد')) {
      final d = parseDuration(n);
      if (d != null) return base.add(d);
    }
    if (n.contains('الان') || n.contains('حالا')) return base;

    final m = RegExp(r'(\d{1,2})(?:\s*[:.]\s*(\d{2}))?').firstMatch(n);
    if (m == null) return null;

    var hour = int.parse(m.group(1)!);
    var minute = int.tryParse(m.group(2) ?? '') ?? 0;
    if (m.group(2) == null && n.contains('ونص')) minute = 30;
    if (hour > 24 || minute > 59) return null;

    final pm = RegExp(r'مساء|عصر|مغرب|عشاء|ليل').hasMatch(n);
    final am = RegExp(r'صباح|فجر').hasMatch(n);
    final noon = n.contains('ظهر');

    if (n.contains('ليل') && hour == 12) {
      hour = 0;
    } else if (pm && hour < 12) {
      hour += 12;
    } else if (am && hour == 12) {
      hour = 0;
    } else if (noon && hour < 7) {
      hour += 12;
    }
    if (hour == 24) hour = 0;

    return DateTime(base.year, base.month, base.day, hour, minute);
  }

  static RecurrenceChoice? parseRecurrence(String raw) {
    final n = normalize(raw);
    final plain = n.replaceAll(RegExp(r'[.!,؟?]'), '').trim();

    if (plain == 'لا' ||
        n.contains('بدون') ||
        n.contains('مره واحده') ||
        n.contains('لا يتكرر') ||
        n.contains('ما يتكرر')) {
      return RecurrenceChoice(Recurrence.none, []);
    }

    const keys = {
      'احد': 7,
      'اثنين': 1,
      'ثلاثاء': 2,
      'اربعاء': 3,
      'خميس': 4,
      'جمعه': 5,
      'سبت': 6,
    };
    final days = <int>[];
    keys.forEach((key, day) {
      if (RegExp('(^|\\s|ال)$key').hasMatch(n)) days.add(day);
    });
    if (days.isNotEmpty) return RecurrenceChoice(Recurrence.weekly, days);

    if (n.contains('يوميا') || n.contains('كل يوم') || n.contains('يومي')) {
      return RecurrenceChoice(Recurrence.daily, []);
    }
    return null;
  }
}
