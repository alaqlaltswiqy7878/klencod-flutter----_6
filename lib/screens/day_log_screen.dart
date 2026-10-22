import 'package:flutter/material.dart';
import '../models/task_item.dart';
import '../services/task_store.dart';
import '../widgets/quick_assistant_fab.dart';

class DayLogScreen extends StatefulWidget {
  const DayLogScreen({super.key});
  @override
  State<DayLogScreen> createState() => _DayLogScreenState();
}

class _DayLogScreenState extends State<DayLogScreen> {
  DateTime _day = DateTime.now();

  List<TaskItem> get _all => TaskStore.getAllTasks().where((t) => t.occursOn(_day) || t.isSnoozedOn(_day)).toList();
  List<TaskItem> get _current {
    final now = DateTime.now();
    final selected = DateTime(_day.year, _day.month, _day.day);
    final today = DateTime(now.year, now.month, now.day);
    if (selected != today) return <TaskItem>[];
    return _all.where((t) => t.isActiveAt(now)).toList();
  }
  List<TaskItem> get _completed => _all.where((t) => t.isDoneOn(_day)).toList();
  List<TaskItem> get _snoozed => _all.where((t) => t.isSnoozedOn(_day)).toList();
  List<TaskItem> get _incomplete => _all.where((t) => !t.isDoneOn(_day) && !_current.contains(t) && !_snoozed.contains(t)).toList();

  Future<void> _pickDay() async {
    final picked = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (picked != null) setState(() => _day = picked);
  }

  @override
  Widget build(BuildContext context) {
    final percent = _all.isEmpty ? 0 : ((_completed.length / _all.length) * 100).round();
    return Scaffold(
      appBar: AppBar(
        title: const Text('السجل اليومي'),
        actions: [IconButton(onPressed: _pickDay, icon: const Icon(Icons.calendar_month), tooltip: 'اختيار يوم')],
      ),
      floatingActionButton: const QuickAssistantFab(),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(child: ListTile(leading: const Icon(Icons.event_note), title: Text(formatYmd(_day)), subtitle: Text('${_all.length} مهام • إنجاز $percent%'))),
          const SizedBox(height: 12),
          _section('حاليًا', Icons.bolt, Colors.amber.shade800, _current),
          _section('القادمة وغير المكتملة', Icons.schedule, Colors.blue, _incomplete),
          _section('المؤجلة', Icons.snooze, Colors.deepOrange, _snoozed),
          _section('المكتملة', Icons.check_circle_outline, Colors.green, _completed),
          if (_all.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('لا يوجد سجل لهذا اليوم'))),
        ],
      ),
    );
  }

  Widget _section(String title, IconData icon, Color color, List<TaskItem> tasks) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: Icon(icon, color: color),
        title: Text('$title (${tasks.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
        children: tasks.isEmpty
            ? [const ListTile(title: Text('لا توجد مهام في هذا القسم'))]
            : tasks.map((t) => ListTile(
                title: Text(t.title),
                subtitle: Text('${formatHm(t.startOn(_day))} - ${formatHm(t.endOn(_day))} • ${t.category}'),
                trailing: t.isDoneOn(_day) ? const Icon(Icons.check, color: Colors.green) : null,
              )).toList(),
      ),
    );
  }
}
