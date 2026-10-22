import 'dart:ui' show DartPluginRegistrant;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../models/task_item.dart';
import 'task_store.dart';

const String kStartChannelId = 'quwat_tasks_start_v3';
const String kEndChannelId = 'quwat_tasks_end_v3';
const String kSnoozeChannelId = 'quwat_tasks_snooze_v3';
const String kActionComplete = 'complete';
const String kActionSnooze = 'snooze';

@pragma('vm:entry-point')
Future<void> notificationTapBackground(NotificationResponse response) async {
  DartPluginRegistrant.ensureInitialized();
  await NotificationService.handleResponse(response);
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static const MethodChannel _channel = MethodChannel('com.quwatalan.app/system_settings');
  static final ValueNotifier<String?> pendingSnoozeTaskId = ValueNotifier<String?>(null);

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  static Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      final name = await _channel.invokeMethod<String>('getTimeZone');
      if (name != null && name.isNotEmpty) tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {}

    const settings = InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher'));
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (r) => handleResponse(r),
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    await _android?.createNotificationChannel(const AndroidNotificationChannel(
      kStartChannelId, 'بداية المهمة',
      description: 'إشعار عند بداية المهمة. يمكنك اختيار النغمة من إعدادات أندرويد.',
      importance: Importance.max,
    ));
    await _android?.createNotificationChannel(const AndroidNotificationChannel(
      kEndChannelId, 'نهاية المهمة',
      description: 'إشعار عند نهاية المهمة. يمكنك اختيار النغمة من إعدادات أندرويد.',
      importance: Importance.max,
    ));
    await _android?.createNotificationChannel(const AndroidNotificationChannel(
      kSnoozeChannelId, 'المهام المؤجلة',
      description: 'إشعار للموعد الجديد بعد تأجيل المهمة.',
      importance: Importance.max,
    ));

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true && launch!.notificationResponse != null) {
      await handleResponse(launch.notificationResponse!);
    }
  }

  static Future<void> requestPermissions() async {
    final android = _android;
    if (android == null) return;
    try { await android.requestNotificationsPermission(); } catch (_) {}
    try {
      if (await android.canScheduleExactNotifications() != true) {
        await android.requestExactAlarmsPermission();
      }
    } catch (_) {}
  }

  static Future<void> openChannelSettings(String channelId) async {
    try { await _channel.invokeMethod('openNotificationChannelSettings', {'channelId': channelId}); } catch (_) {}
  }

  static Future<void> handleResponse(NotificationResponse response) async {
    final taskId = response.payload;
    if (taskId == null || taskId.isEmpty) return;
    if (response.actionId == kActionComplete) {
      await TaskStore.init();
      await TaskStore.markDone(taskId, DateTime.now());
    } else if (response.actionId == kActionSnooze) {
      pendingSnoozeTaskId.value = taskId;
    }
  }

  static int _baseId(String id) {
    final n = int.tryParse(id) ?? id.hashCode;
    return (n.abs() % 100000000) * 10;
  }

  static NotificationDetails _details(String channelId, String channelName, {bool actions = false}) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId, channelName,
        channelDescription: 'إشعارات تطبيق قوة الآن',
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        actions: actions ? const [
          AndroidNotificationAction(kActionComplete, 'إتمام المهمة', showsUserInterface: false, cancelNotification: true),
          AndroidNotificationAction(kActionSnooze, 'لاحقاً', showsUserInterface: true, cancelNotification: true),
        ] : null,
      ),
    );
  }

  static tz.TZDateTime _nextAt(DateTime time, {DateTime? notBefore, int? weekday}) {
    final now = tz.TZDateTime.now(tz.local);
    var first = tz.TZDateTime(tz.local, now.year, now.month, now.day, time.hour, time.minute);
    if (notBefore != null) {
      final nb = tz.TZDateTime(tz.local, notBefore.year, notBefore.month, notBefore.day, time.hour, time.minute);
      if (nb.isAfter(first)) first = nb;
    }
    for (var i = 0; i < 16; i++) {
      final cand = tz.TZDateTime(tz.local, first.year, first.month, first.day + i, time.hour, time.minute);
      if (!cand.isAfter(now)) continue;
      if (weekday != null && cand.weekday != weekday) continue;
      return cand;
    }
    return first.add(const Duration(days: 1));
  }

  static Future<void> _zoned(int id, TaskItem task, tz.TZDateTime when, DateTimeComponents? match,
      {required String channelId, required String channelName, required String title, bool actions = false}) async {
    Future<void> go(AndroidScheduleMode mode) => _plugin.zonedSchedule(
      id, title, task.title, when, _details(channelId, channelName, actions: actions),
      androidScheduleMode: mode,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: match,
      payload: task.id,
    );
    try { await go(AndroidScheduleMode.exactAllowWhileIdle); }
    catch (_) { try { await go(AndroidScheduleMode.inexactAllowWhileIdle); } catch (_) {} }
  }

  static Future<void> scheduleTask(TaskItem task) async {
    await cancelTask(task.id);
    final base = _baseId(task.id);
    final validEnd = task.endTime.isAfter(DateTime.now());
    Future<void> schedulePair(DateTime start, DateTime end, DateTimeComponents? match, int offset) async {
      if (start.isAfter(DateTime.now())) {
        await _zoned(base + offset, task, tz.TZDateTime.from(start, tz.local), match,
          channelId: kStartChannelId, channelName: 'بداية المهمة', title: 'حان وقت المهمة 💪', actions: true);
      }
      if (end.isAfter(DateTime.now())) {
        await _zoned(base + offset + 1, task, tz.TZDateTime.from(end, tz.local), match,
          channelId: kEndChannelId, channelName: 'نهاية المهمة', title: 'انتهى وقت المهمة', actions: false);
      }
    }

    switch (task.recurrence) {
      case Recurrence.none:
        if (!task.isCompleted && task.startTime.isAfter(DateTime.now())) {
          await schedulePair(task.startTime, task.endTime, null, 0);
        } else if (!task.isCompleted && validEnd) {
          await _zoned(base + 1, task, tz.TZDateTime.from(task.endTime, tz.local), null,
            channelId: kEndChannelId, channelName: 'نهاية المهمة', title: 'انتهى وقت المهمة');
        }
        break;
      case Recurrence.daily:
        await schedulePair(_nextAt(task.startTime, notBefore: task.startTime),
          _nextAt(task.endTime, notBefore: task.startTime), DateTimeComponents.time, 0);
        break;
      case Recurrence.weekly:
        for (final d in task.weekdays) {
          await schedulePair(_nextAt(task.startTime, notBefore: task.startTime, weekday: d),
            _nextAt(task.endTime, notBefore: task.startTime, weekday: d),
            DateTimeComponents.dayOfWeekAndTime, d * 2);
        }
        break;
    }
  }

  static Future<void> scheduleOneOff(TaskItem task, DateTime when) async {
    await _plugin.cancel(_baseId(task.id) + 90);
    if (!when.isAfter(DateTime.now())) return;
    await _zoned(_baseId(task.id) + 90, task, tz.TZDateTime.from(when, tz.local), null,
      channelId: kSnoozeChannelId, channelName: 'المهام المؤجلة', title: 'حان موعد المهمة المؤجلة 💪', actions: true);
  }

  static Future<void> cancelTask(String taskId) async {
    final base = _baseId(taskId);
    for (var i = 0; i <= 90; i++) await _plugin.cancel(base + i);
  }
}
