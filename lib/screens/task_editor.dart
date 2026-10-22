import 'package:flutter/material.dart';
import '../models/sub_task.dart';
import '../models/task_item.dart';
import '../services/task_store.dart';
import '../services/notification_service.dart';
import '../widgets/quick_assistant_fab.dart';

class _SubEdit {
  final String id;
  final TextEditingController controller;
  bool done;

  _SubEdit({required this.id, required String title, this.done = false})
      : controller = TextEditingController(text: title);
}

class TaskEditorScreen extends StatefulWidget {
  final TaskItem? task;

  const TaskEditorScreen({super.key, this.task});

  @override
  State<TaskEditorScreen> createState() => _TaskEditorScreenState();
}

class _TaskEditorScreenState extends State<TaskEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descController;
  late DateTime _startTime;
  late DateTime _endTime;
  late Recurrence _recurrence;
  late String _category;
  late String _priority;
  final Set<int> _weekdays = {};
  final List<_SubEdit> _subs = [];
  int _subCounter = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final t = widget.task;
    _titleController = TextEditingController(text: t?.title ?? '');
    _descController = TextEditingController(text: t?.description ?? '');
    _startTime = t?.startTime ?? now.add(const Duration(minutes: 5));
    _endTime = t?.endTime ?? now.add(const Duration(hours: 1));
    _recurrence = t?.recurrence ?? Recurrence.none;
    _category = t?.category ?? 'عام';
    _priority = t?.priority ?? 'متوسطة';
    _weekdays.addAll(t?.weekdays ?? const <int>[]);
    for (final s in t?.subTasks ?? const <SubTask>[]) {
      _subs.add(_SubEdit(id: s.id, title: s.title, done: s.isDone));
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    for (final s in _subs) {
      s.controller.dispose();
    }
    super.dispose();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _startTime,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    setState(() {
      final dur = _endTime.difference(_startTime);
      _startTime = DateTime(d.year, d.month, d.day, _startTime.hour, _startTime.minute);
      _endTime = _startTime.add(dur);
    });
  }

  Future<void> _pickTime(bool isStart) async {
    final initial = isStart ? _startTime : _endTime;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;

    final selected = DateTime(_startTime.year, _startTime.month, _startTime.day, time.hour, time.minute);
    if (isStart) {
      var dur = _endTime.difference(_startTime);
      if (dur.inMinutes <= 0) dur = const Duration(hours: 1);
      setState(() {
        _startTime = selected;
        _endTime = selected.add(dur);
      });
    } else {
      if (!selected.isAfter(_startTime)) {
        _snack('وقت الانتهاء يجب أن يكون بعد وقت البدء');
        return;
      }
      setState(() => _endTime = selected);
    }
  }

  void _addSub() {
    setState(() {
      _subCounter++;
      _subs.add(_SubEdit(
        id: '${DateTime.now().millisecondsSinceEpoch}_$_subCounter',
        title: '',
      ));
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_recurrence == Recurrence.weekly && _weekdays.isEmpty) {
      _snack('اختر يوماً واحداً على الأقل للتكرار الأسبوعي');
      return;
    }

    final subTasks = _subs
        .where((s) => s.controller.text.trim().isNotEmpty)
        .map((s) => SubTask(id: s.id, title: s.controller.text.trim(), isDone: s.done))
        .toList();

    final item = TaskItem(
      id: widget.task?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: _titleController.text.trim(),
      description: _descController.text.trim(),
      startTime: _startTime,
      endTime: _endTime,
      isCompleted: widget.task?.isCompleted ?? false,
      category: _category,
      priority: _priority,
      recurrence: _recurrence,
      weekdays: _recurrence == Recurrence.weekly ? (_weekdays.toList()..sort()) : <int>[],
      subTasks: subTasks,
      completedDates: List<String>.from(widget.task?.completedDates ?? const <String>[]),
      snoozedDates: List<String>.from(widget.task?.snoozedDates ?? const <String>[]),
    );

    final conflict = TaskStore.findOverlap(item);
    if (conflict != null) {
      _snack('لا يمكن الحفظ: تتداخل مع «${conflict.title}» من ${formatHm(conflict.startTime)} إلى ${formatHm(conflict.endTime)}.');
      return;
    }

    await TaskStore.saveTask(item);
    await NotificationService.scheduleTask(item);

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final isRecurring = _recurrence != Recurrence.none;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.task == null ? 'إضافة مهمة جديدة' : 'تعديل المهمة'),
      ),
      floatingActionButton: const QuickAssistantFab(),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'عنوان المهمة',
                  border: OutlineInputBorder(),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'يرجى كتابة العنوان' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'تفاصيل إضافية (اختياري)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(labelText: 'التصنيف', border: OutlineInputBorder()),
                items: const ['عام', 'عمل', 'دراسة', 'رياضة', 'شخصي', 'عائلة']
                    .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                    .toList(),
                onChanged: (value) => setState(() => _category = value ?? 'عام'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _priority,
                decoration: const InputDecoration(labelText: 'درجة الأهمية', border: OutlineInputBorder()),
                items: const ['منخفضة', 'متوسطة', 'عالية', 'عاجلة']
                    .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                    .toList(),
                onChanged: (value) => setState(() => _priority = value ?? 'متوسطة'),
              ),
              const SizedBox(height: 12),
              ListTile(
                title: Text(isRecurring ? 'يبدأ التكرار من' : 'التاريخ'),
                subtitle: Text(formatYmd(_startTime)),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: _pickDate,
              ),
              ListTile(
                title: const Text('وقت البدء'),
                subtitle: Text(formatHm(_startTime)),
                trailing: const Icon(Icons.access_time),
                onTap: () => _pickTime(true),
              ),
              ListTile(
                title: const Text('وقت الانتهاء'),
                subtitle: Text(formatHm(_endTime)),
                trailing: const Icon(Icons.access_time_filled),
                onTap: () => _pickTime(false),
              ),
              const Divider(),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('التكرار', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              SegmentedButton<Recurrence>(
                segments: const [
                  ButtonSegment(value: Recurrence.none, label: Text('مرة واحدة')),
                  ButtonSegment(value: Recurrence.daily, label: Text('يومياً')),
                  ButtonSegment(value: Recurrence.weekly, label: Text('أيام محددة')),
                ],
                selected: {_recurrence},
                onSelectionChanged: (s) => setState(() => _recurrence = s.first),
              ),
              if (_recurrence == Recurrence.weekly) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: kWeekdayOrder.map((d) {
                    return FilterChip(
                      label: Text(kWeekdayNames[d]!),
                      selected: _weekdays.contains(d),
                      onSelected: (v) => setState(() {
                        if (v) {
                          _weekdays.add(d);
                        } else {
                          _weekdays.remove(d);
                        }
                      }),
                    );
                  }).toList(),
                ),
              ],
              const Divider(height: 32),
              const Text('المهام الفرعية', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ..._subs.map((s) {
                return Row(
                  children: [
                    Checkbox(
                      value: s.done,
                      onChanged: (v) => setState(() => s.done = v ?? false),
                    ),
                    Expanded(
                      child: TextField(
                        controller: s.controller,
                        decoration: const InputDecoration(
                          hintText: 'خطوة صغيرة...',
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.redAccent),
                      onPressed: () => setState(() => _subs.remove(s)),
                    ),
                  ],
                );
              }),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: _addSub,
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة مهمة فرعية'),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('حفظ المهمة', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
