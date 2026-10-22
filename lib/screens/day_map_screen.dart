import 'package:flutter/material.dart';
import '../models/task_item.dart';
import '../services/task_store.dart';
import '../widgets/quick_assistant_fab.dart';

class DayMapScreen extends StatefulWidget {
  final DateTime day;
  const DayMapScreen({super.key, required this.day});
  @override State<DayMapScreen> createState() => _DayMapScreenState();
}

class _DayMapScreenState extends State<DayMapScreen> {
  late DateTime _day;
  @override
  void initState() { super.initState(); _day = DateTime(widget.day.year, widget.day.month, widget.day.day); }
  List<TaskItem> get _tasks => TaskStore.getAllTasks().where((t) => t.occursOn(_day)).toList()..sort((a, b) => a.startOn(_day).compareTo(b.startOn(_day)));
  String _duration(Duration d) { final h=d.inHours, m=d.inMinutes.remainder(60); if (h==0) return '$m دقيقة'; if (m==0) return '$h ساعة'; return '$h س و $m د'; }
  void _move(int days) => setState(() => _day = _day.add(Duration(days: days)));

  @override
  Widget build(BuildContext context) {
    final tasks = _tasks;
    final busy = tasks.fold<Duration>(Duration.zero, (sum, t) => sum + t.duration);
    final free = const Duration(hours: 24) - busy;
    final usage = (busy.inMinutes / (24 * 60)).clamp(0.0, 1.0);
    return Scaffold(
      appBar: AppBar(title: const Text('خريطة يومي'), actions: [
        IconButton(onPressed: () => _move(-1), icon: const Icon(Icons.chevron_right)),
        IconButton(onPressed: () => setState(() => _day = DateTime.now()), icon: const Icon(Icons.today)),
        IconButton(onPressed: () => _move(1), icon: const Icon(Icons.chevron_left)),
      ]),
      floatingActionButton: const QuickAssistantFab(),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(formatYmd(_day), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('مشغول: ${_duration(busy)}'), Text('متاح: ${_duration(free.isNegative ? Duration.zero : free)}')]),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: usage, minHeight: 10, borderRadius: BorderRadius.circular(8)),
          const SizedBox(height: 8), Text('${tasks.length} مهام — ${(usage * 100).round()}% من اليوم مجدول'),
        ]))),
        const SizedBox(height: 12),
        if (tasks.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('لا توجد مهام في هذا اليوم')))) else ..._timelineWithGaps(tasks),
      ]),
    );
  }

  List<Widget> _timelineWithGaps(List<TaskItem> tasks) {
    final out = <Widget>[];
    var cursor = DateTime(_day.year, _day.month, _day.day);
    for (final task in tasks) {
      final start = task.startOn(_day);
      if (start.isAfter(cursor)) out.add(_gap(cursor, start));
      out.add(_timelineTask(task));
      final end = task.endOn(_day);
      if (end.isAfter(cursor)) cursor = end;
    }
    final midnight = DateTime(_day.year, _day.month, _day.day + 1);
    if (cursor.isBefore(midnight)) out.add(_gap(cursor, midnight));
    return out;
  }

  Widget _gap(DateTime start, DateTime end) => Card(color: Theme.of(context).colorScheme.surfaceContainerLowest, child: ListTile(leading: const Icon(Icons.free_breakfast_outlined), title: const Text('فترة فارغة'), subtitle: Text('${formatHm(start)} - ${formatHm(end)}')));

  Widget _timelineTask(TaskItem task) {
    final start = task.startOn(_day), end = task.endOn(_day);
    final color = task.category == 'عمل' ? Colors.blue : task.category == 'رياضة' ? Colors.orange : const Color(0xFF126B50);
    return Card(child: ListTile(leading: Container(width: 6, height: 52, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6))), title: Text(task.title, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text('${formatHm(start)} - ${formatHm(end)}  •  ${task.category}\n${_duration(task.duration)}'), isThreeLine: true, trailing: Icon(task.isDoneOn(_day) ? Icons.check_circle : Icons.schedule, color: task.isDoneOn(_day) ? Colors.green : Colors.grey)));
  }
}
