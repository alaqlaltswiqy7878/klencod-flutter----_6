import 'dart:async';
import 'package:flutter/material.dart';
import '../models/task_item.dart';
import '../services/notification_service.dart';
import '../services/task_store.dart';
import '../services/settings_store.dart';
import 'assistant_screen.dart';
import 'settings_screen.dart';
import 'task_editor.dart';
import 'day_map_screen.dart';
import 'day_log_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<TaskItem> _tasks = [];
  bool _isLoading = true;
  bool _snoozeOpen = false;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    TaskStore.changes.addListener(_loadTasks);
    NotificationService.pendingSnoozeTaskId.addListener(_checkSnooze);
    _loadTasks();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) { if (mounted) setState(() {}); });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _checkSnooze();
      await NotificationService.requestPermissions();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    TaskStore.changes.removeListener(_loadTasks);
    NotificationService.pendingSnoozeTaskId.removeListener(_checkSnooze);
    _clock?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onResumed();
    }
  }

  Future<void> _onResumed() async {
    // قد تكون مهمة أُنجزت من زر الإشعار في الخلفية
    await TaskStore.reload();
    _checkSnooze();
  }

  void _loadTasks() {
    if (!mounted) return;
    setState(() {
      _tasks = List<TaskItem>.from(TaskStore.getAllTasks());
      _isLoading = false;
    });
  }

  // ---------- التأجيل (زر "لاحقاً") ----------

  Future<void> _checkSnooze() async {
    final id = NotificationService.pendingSnoozeTaskId.value;
    if (id == null || _snoozeOpen || !mounted) return;
    NotificationService.pendingSnoozeTaskId.value = null;
    final task = TaskStore.getById(id);
    if (task == null) return;
    _snoozeOpen = true;
    await _showSnoozeSheet(task);
    _snoozeOpen = false;
  }

  Future<void> _showSnoozeSheet(TaskItem task) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'هل تريد تأجيل المهمة "${task.title}" إلى:',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('بعد ساعة'),
              onTap: () => Navigator.pop(ctx, 'hour'),
            ),
            ListTile(
              leading: const Icon(Icons.wb_sunny_outlined),
              title: const Text('الغد'),
              onTap: () => Navigator.pop(ctx, 'tomorrow'),
            ),
            ListTile(
              leading: const Icon(Icons.date_range_outlined),
              title: const Text('بعد أسبوع'),
              onTap: () => Navigator.pop(ctx, 'week'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_calendar_outlined),
              title: const Text('تخصيص (اختيار وقت وتاريخ)'),
              onTap: () => Navigator.pop(ctx, 'custom'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    final now = DateTime.now();
    DateTime? newStart;
    switch (choice) {
      case 'hour':
        newStart = now.add(const Duration(hours: 1));
        break;
      case 'tomorrow':
        newStart = DateTime(now.year, now.month, now.day + 1, task.startTime.hour, task.startTime.minute);
        break;
      case 'week':
        newStart = now.add(const Duration(days: 7));
        break;
      case 'custom':
        final date = await showDatePicker(
          context: context,
          initialDate: now,
          firstDate: DateTime(now.year, now.month, now.day),
          lastDate: DateTime(now.year + 2),
        );
        if (date == null || !mounted) return;
        final time = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
        );
        if (time == null) return;
        newStart = DateTime(date.year, date.month, date.day, time.hour, time.minute);
        break;
    }
    if (newStart == null) return;
    await _applySnooze(task, newStart);
  }

  Future<void> _applySnooze(TaskItem task, DateTime newStart) async {
    final newEnd = newStart.add(task.duration);
    final conflict = TaskStore.findOverlapAt(task, newStart, newEnd);
    if (conflict != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('لا يمكن التأجيل: يتداخل مع «${conflict.title}» من ${formatHm(conflict.startOn(newStart))} إلى ${formatHm(conflict.endOn(newStart))}.')),
        );
      }
      return;
    }
    final todayKey = TaskItem.dateKey(DateTime.now());
    if (!task.snoozedDates.contains(todayKey)) task.snoozedDates.add(todayKey);
    if (task.isRecurring) {
      await NotificationService.scheduleOneOff(task, newStart);
      await TaskStore.saveTask(task);
    } else {
      final dur = task.duration;
      task.startTime = newStart;
      task.endTime = newStart.add(dur);
      task.isCompleted = false;
      await TaskStore.saveTask(task);
      await NotificationService.scheduleTask(task);
    }
    _loadTasks();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم التأجيل إلى ${formatYmd(newStart)} ${formatHm(newStart)}')),
      );
    }
  }

  // ---------- بيانات العرض ----------

  List<TaskItem> get _todayTasks {
    final now = DateTime.now();
    final list = _tasks.where((t) => t.occursOn(now)).toList();
    list.sort((a, b) => a.startOn(now).compareTo(b.startOn(now)));
    return list;
  }

  List<TaskItem> get _laterTasks {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final list = _tasks.where((t) {
      final d = DateTime(t.startTime.year, t.startTime.month, t.startTime.day);
      return !t.isRecurring && !t.isCompleted && d.isAfter(today);
    }).toList();
    list.sort((a, b) => a.startTime.compareTo(b.startTime));
    return list;
  }

  TaskItem? get _currentActiveTask {
    final now = DateTime.now();
    for (final t in _tasks) {
      if (t.isActiveAt(now)) return t;
    }
    return null;
  }

  MapEntry<TaskItem, DateTime>? get _upcoming {
    final now = DateTime.now();
    MapEntry<TaskItem, DateTime>? best;
    for (final t in _tasks) {
      final next = t.nextOccurrenceAfter(now);
      if (next == null) continue;
      if (best == null || next.isBefore(best.value)) {
        best = MapEntry(t, next);
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(SettingsStore.displayName.isEmpty ? 'قوة الآن 💪' : 'مرحبًا ${SettingsStore.displayName}')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async { await TaskStore.reload(); },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  if (SettingsStore.displayName.isNotEmpty)
                    Text('أهلًا ${SettingsStore.displayName}، ركّز على الخطوة التالية.', style: Theme.of(context).textTheme.titleMedium),
                  _buildProgressSection(),
                  const SizedBox(height: 12),
                  _buildNowSection(),
                  const SizedBox(height: 12),
                  _buildUpcomingSection(),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const TaskEditorScreen()));
          if (result == true) _loadTasks();
        },
        label: const Text('إضافة مهمة'), icon: const Icon(Icons.add),
        backgroundColor: const Color(0xFF126B50), foregroundColor: Colors.white,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(), notchMargin: 8,
        child: SizedBox(height: 62, child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          IconButton(tooltip: 'خريطة اليوم', icon: const Icon(Icons.timeline), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DayMapScreen(day: DateTime.now())))),
          IconButton(tooltip: 'السجل', icon: const Icon(Icons.event_note_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DayLogScreen()))),
          const SizedBox(width: 54),
          IconButton(tooltip: 'نيكو', icon: const Icon(Icons.auto_awesome), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AssistantChooserScreen()))),
          IconButton(tooltip: 'الإعدادات', icon: const Icon(Icons.settings_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
        ])),
      ),
    );
  }

  Widget _buildNowSection() {
    final active = _currentActiveTask;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final activeBg = isDark ? const Color(0xFF1B3A1E) : const Color(0xFFE8F5E9);
    final activeTitle = isDark ? const Color(0xFFA5D6A7) : const Color(0xFF1B5E20);

    final now = DateTime.now();
    final start = active?.startOn(now);
    final end = active?.endOn(now);
    final remaining = end?.difference(now);
    return Card(
      color: active != null ? activeBg : cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: active != null ? Colors.green : Colors.grey.shade400),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt, color: active != null ? Colors.amber.shade800 : Colors.grey),
                const SizedBox(width: 8),
                Text(
                  'ماذا أفعل الآن؟',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (active != null) ...[
              Text(
                active.title,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: activeTitle),
              ),
              const SizedBox(height: 8),
              Text('${formatHm(start!)} - ${formatHm(end!)}'),
              Text('المتبقي: ${remaining!.inHours > 0 ? '${remaining.inHours} س و ' : ''}${remaining.inMinutes.remainder(60)} د'),
              if (active.description.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(active.description),
              ],
              const SizedBox(height: 6),
              Text('التصنيف: ${active.category}'),
              Text('الأهمية: ${active.priority}'),
              if (active.subTasks.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('المهام الفرعية: ${active.subTasks.where((s) => s.isDone).length}/${active.subTasks.length}'),
              ],
            ] else ...[
              const Text('لا توجد مهمة جارية حاليًا.', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              if (_upcoming != null) ...[
                const SizedBox(height: 8),
                Text('المهمة القادمة: ${_upcoming!.key.title}'),
                Text('تبدأ: ${formatYmd(_upcoming!.value)} ${formatHm(_upcoming!.value)}'),
              ] else const Padding(padding: EdgeInsets.only(top: 8), child: Text('لا توجد مهمة قادمة. أضف خطوة صغيرة الآن.')),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProgressSection() {
    final now = DateTime.now();
    final today = _tasks.where((t) => t.occursOn(now)).toList();
    final completedToday = today.where((t) => t.isDoneOn(now)).length;
    final weekDone = <String>{};
    for (var i = 0; i < 7; i++) {
      final day = DateTime(now.year, now.month, now.day - i);
      if (_tasks.any((t) => t.occursOn(day) && t.isDoneOn(day))) {
        weekDone.add(TaskItem.dateKey(day));
      }
    }
    var streak = 0;
    for (var i = 0; i < 30; i++) {
      final day = DateTime(now.year, now.month, now.day - i);
      if (!_tasks.any((t) => t.occursOn(day) && t.isDoneOn(day))) break;
      streak++;
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _stat(Icons.today_outlined, '$completedToday/${today.length}', 'اليوم'),
            _stat(Icons.local_fire_department_outlined, '$streak', 'سلسلة أيام'),
            _stat(Icons.insights_outlined, '${weekDone.length}', 'أيام نشطة'),
          ],
        ),
      ),
    );
  }

  Widget _stat(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF2E7D32)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  Widget _buildUpcomingSection() {
    final upcoming = _upcoming;
    if (upcoming == null) return const SizedBox.shrink();
    return Card(
      child: ListTile(
        leading: const Icon(Icons.access_time, color: Colors.blue),
        title: Text('المهمة القادمة: ${upcoming.key.title}'),
        subtitle: Text('البدء: ${formatHm(upcoming.value)}'),
      ),
    );
  }

  Widget _buildTaskCard(TaskItem task, DateTime day) {
    final done = task.isDoneOn(day);
    final isToday = TaskItem.dateKey(day) == TaskItem.dateKey(DateTime.now());
    final timeText = '${formatHm(task.startOn(day))} - ${formatHm(task.endOn(day))}';
    final lines = <String>[
      isToday ? timeText : '${formatYmd(day)}  $timeText',
      if (task.isRecurring) task.recurrenceLabel,
      if (task.subTasks.isNotEmpty)
        'المهام الفرعية: ${task.subTasks.where((s) => s.isDone).length}/${task.subTasks.length}',
    ];

    return Card(
      child: Column(
        children: [
          ListTile(
            isThreeLine: lines.length > 2,
            leading: Checkbox(
              value: done,
              activeColor: const Color(0xFF2E7D32),
              onChanged: (val) async {
                task.setDoneOn(day, val ?? false);
                await TaskStore.saveTask(task);
                if (!task.isRecurring) {
                  if (task.isCompleted) {
                    await NotificationService.cancelTask(task.id);
                  } else {
                    await NotificationService.scheduleTask(task);
                  }
                }
                _loadTasks();
              },
            ),
            title: Text(
              task.title,
              style: TextStyle(
                decoration: done ? TextDecoration.lineThrough : null,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(lines.join('\n')),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: () async {
                await NotificationService.cancelTask(task.id);
                await TaskStore.deleteTask(task.id);
                _loadTasks();
              },
            ),
            onTap: () async {
              final res = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => TaskEditorScreen(task: task)),
              );
              if (res == true) _loadTasks();
            },
          ),
          ...task.subTasks.map(
            (st) => CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsetsDirectional.only(start: 56, end: 16),
              value: st.isDone,
              title: Text(
                st.title,
                style: TextStyle(decoration: st.isDone ? TextDecoration.lineThrough : null),
              ),
              onChanged: (v) async {
                st.isDone = v ?? false;
                await TaskStore.saveTask(task);
                _loadTasks();
              },
            ),
          ),
        ],
      ),
    );
  }
}
