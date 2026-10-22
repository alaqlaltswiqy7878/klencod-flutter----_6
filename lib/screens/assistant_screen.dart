import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../models/task_item.dart';
import '../services/ai_assistant_service.dart';
import '../services/task_store.dart';
import 'niko_setup_screen.dart';

enum AssistantMode { general, timeManagement }

class AssistantChooserScreen extends StatelessWidget {
  const AssistantChooserScreen({super.key});
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('اختر المساعد')), body: ListView(padding: const EdgeInsets.all(20), children: [
    _choice(context, AssistantMode.general, Icons.auto_awesome, 'نيكو العام', 'محادثة مفتوحة في الموضوعات المتنوعة.'),
    _choice(context, AssistantMode.timeManagement, Icons.schedule, 'مساعد تنظيم الوقت', 'يفهم جدولك المحلي ويقترح دون تعديل أي مهمة بلا موافقة.'),
  ]));
  Widget _choice(BuildContext context, AssistantMode mode, IconData icon, String title, String subtitle) => Card(child: ListTile(contentPadding: const EdgeInsets.all(16), leading: CircleAvatar(child: Icon(icon)), title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(subtitle), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AssistantScreen(mode: mode)))));
}

class AssistantScreen extends StatefulWidget {
  final AssistantMode mode;
  const AssistantScreen({super.key, this.mode = AssistantMode.general});
  @override State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _speech = SpeechToText();
  final _tts = FlutterTts();
  final List<Map<String, String>> _messages = [];
  final List<double> _levels = List<double>.filled(48, 0.0);
  Timer? _ticker;
  int _seconds = 0;
  String _startText = '';
  bool _sending = false, _listening = false, _ttsEnabled = false, _setupOpened = false, _speechReady = false, _restarting = false;
  String? _localeId;
  String _speechBuffer = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _messages.add({'role': 'assistant', 'text': widget.mode == AssistantMode.general ? 'أهلًا بك، أنا نيكو. كيف أستطيع مساعدتك؟' : 'أنا مساعد تنظيم الوقت. سأعتمد على جدولك المحلي دون اختراع مهام أو تعديلها دون موافقتك.'});
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureSetup());
  }

  Future<void> _ensureSetup() async {
    if (_setupOpened || AiAssistantService.isConfigured || !mounted) return;
    _setupOpened = true;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const NikoSetupScreen()));
    _setupOpened = false;
  }

  @override void dispose() { WidgetsBinding.instance.removeObserver(this); _ticker?.cancel(); _speech.stop(); _tts.stop(); _controller.dispose(); _scroll.dispose(); super.dispose(); }
  @override void didChangeAppLifecycleState(AppLifecycleState state) { if (state != AppLifecycleState.resumed && _listening) _stopListening(); }

  Future<void> _toggleMic() async {
    if (_listening) { await _stopListening(); return; }
    if (!_speechReady) {
      _speechReady = await _speech.initialize(onStatus: (status) { if ((status == 'done' || status == 'notListening') && _listening && !_restarting) _restartListening(); }, onError: (_) { _ticker?.cancel(); if (mounted) setState(() => _listening = false); });
      if (_speechReady) { for (final l in await _speech.locales()) { if (l.localeId.toLowerCase().startsWith('ar')) { _localeId = l.localeId; break; } } }
    }
    if (!_speechReady) { _error('لم تُمنح صلاحية الميكروفون أو التعرف الصوتي غير متاح.'); return; }
    _speechBuffer = _controller.text.trim();
    _startText = _controller.text;
    _seconds = 0;
    for (var i = 0; i < _levels.length; i++) { _levels[i] = 0.0; }
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() => _seconds++); });
    setState(() => _listening = true);
    await _listenOnce();
  }

  Future<void> _listenOnce() async {
    if (!_listening) return;
    await _speech.listen(localeId: _localeId, listenFor: const Duration(minutes: 5), pauseFor: const Duration(seconds: 2), listenMode: ListenMode.dictation, onSoundLevelChange: _onLevel, onResult: (r) {
      if (!mounted || r.recognizedWords.trim().isEmpty) return;
      final words = r.recognizedWords.trim();
      final text = [_speechBuffer, words].where((x) => x.isNotEmpty).join(' ');
      setState(() { _controller.text = text; _controller.selection = TextSelection.collapsed(offset: text.length); });
      if (r.finalResult) _speechBuffer = text;
    });
  }

  Future<void> _restartListening() async { if (_restarting || !_listening) return; _restarting = true; await Future<void>.delayed(const Duration(milliseconds: 180)); _restarting = false; if (mounted && _listening) await _listenOnce(); }
  Future<void> _stopListening() async { if (!_listening) return; _ticker?.cancel(); setState(() => _listening = false); _restarting = false; await _speech.stop(); }

  Future<void> _send() async {
    if (_sending || _listening) return;
    if (!AiAssistantService.isConfigured) { await _ensureSetup(); if (!AiAssistantService.isConfigured) return; }
    final text = _controller.text.trim(); if (text.isEmpty) return;
    setState(() { _sending = true; _controller.clear(); _messages.add({'role': 'user', 'text': text}); }); _scrollEnd();
    try {
      final contextText = widget.mode == AssistantMode.timeManagement ? _timeContext() : null;
      final answer = await AiAssistantService.send(messages: _messages.map((m) => {'role': m['role'] ?? 'user', 'text': m['text'] ?? ''}).toList(), systemInstruction: widget.mode == AssistantMode.general ? 'أنت نيكو، مساعد عربي عام. كن واضحًا ومختصرًا ولا تدّع تنفيذ شيء لم يحدث.' : 'أنت نيكو في وضع تنظيم الوقت. استخدم سياق الجدول المرفق فقط. لا تخترع مهامًا. اقترح التغييرات واطلب موافقة صريحة قبل التنفيذ. لا تعتبر انتهاء الوقت إنجازًا.\nالسياق المحلي:\n$contextText');
      if (!mounted) return; setState(() => _messages.add({'role': 'assistant', 'text': answer})); _scrollEnd(); if (_ttsEnabled) await _speak(answer);
    } catch (e) { if (mounted) setState(() => _messages.add({'role': 'assistant', 'text': e.toString().replaceFirst('Exception: ', '')})); }
    finally { if (mounted) setState(() => _sending = false); }
  }

  String _timeContext() { final now = DateTime.now(); final lines = <String>[]; for (final t in TaskStore.getAllTasks()) { if (t.occursOn(now) || t.nextOccurrenceAfter(now) != null) { final day = t.occursOn(now) ? now : t.nextOccurrenceAfter(now)!; lines.add('${t.title} | ${formatYmd(day)} ${formatHm(t.startOn(day))}-${formatHm(t.endOn(day))} | ${t.isDoneOn(day) ? 'مكتملة' : 'غير مكتملة'}'); } } return lines.isEmpty ? 'لا توجد مهام قادمة أو حالية في البيانات المحلية.' : lines.take(30).join('\n'); }
  Future<void> _speak(String text) async { try { await _tts.setLanguage('ar-SA'); await _tts.setSpeechRate(0.48); await _tts.speak(text); } catch (_) {} }
  void _error(String text) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text))); }
  void _scrollEnd() => WidgetsBinding.instance.addPostFrameCallback((_) { if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 220), curve: Curves.easeOut); });

  void _onLevel(double level) {
    if (!mounted || !_listening) return;
    final v = ((level + 2) / 12).clamp(0.0, 1.0).toDouble();
    setState(() { _levels.removeAt(0); _levels.add(v); });
  }

  Future<void> _cancelListening() async {
    if (!_listening) return;
    _ticker?.cancel(); _restarting = false;
    setState(() { _listening = false; _controller.text = _startText; _controller.selection = TextSelection.collapsed(offset: _startText.length); });
    await _speech.cancel();
  }

  Widget _recordingBar() {
    final c = Theme.of(context).colorScheme;
    final t = '${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')}';
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(28)),
      child: Row(children: [
        IconButton(tooltip: 'إلغاء', icon: const Icon(Icons.close), onPressed: _cancelListening),
        Expanded(child: SizedBox(height: 36, child: CustomPaint(painter: _LevelWavePainter(List<double>.from(_levels), c.primary)))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(t)),
        IconButton.filled(tooltip: 'تم', icon: const Icon(Icons.check), onPressed: _stopListening),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(widget.mode == AssistantMode.general ? 'نيكو' : 'تنظيم الوقت'), actions: [IconButton(tooltip: 'قراءة الردود', icon: Icon(_ttsEnabled ? Icons.volume_up : Icons.volume_off), onPressed: () => setState(() => _ttsEnabled = !_ttsEnabled))]), body: Column(children: [
    Expanded(child: ListView.builder(controller: _scroll, padding: const EdgeInsets.all(12), itemCount: _messages.length, itemBuilder: (_, i) { final m = _messages[i]; final user = m['role'] == 'user'; return Align(alignment: user ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd, child: Container(constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .84), margin: const EdgeInsets.symmetric(vertical: 5), padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: user ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(m['text'] ?? '', style: TextStyle(color: user ? Colors.white : null, height: 1.45)), if (!user) Align(alignment: AlignmentDirectional.centerEnd, child: IconButton(icon: const Icon(Icons.volume_up_outlined, size: 19), onPressed: () => _speak(m['text'] ?? ''))) ]))); })),
    if (_sending) const Padding(padding: EdgeInsets.all(6), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 8), Text('نيكو يفكر...')])),
    if (_listening && _controller.text.trim().isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(18, 0, 18, 6), child: Text(_controller.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).hintColor))),
    SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(8, 4, 8, 8), child: _listening ? _recordingBar() : Row(children: [IconButton(tooltip: _listening ? 'إيقاف التسجيل' : 'تسجيل صوتي', icon: Icon(_listening ? Icons.stop : Icons.mic_none, color: _listening ? Colors.red : Theme.of(context).colorScheme.primary), onPressed: _toggleMic), Expanded(child: TextField(controller: _controller, minLines: 1, maxLines: 5, textInputAction: TextInputAction.newline, decoration: InputDecoration(hintText: _listening ? 'أستمع إليك...' : 'اكتب رسالتك...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(22))), onSubmitted: (_) => _send())), IconButton(tooltip: 'إرسال', icon: const Icon(Icons.send), onPressed: _sending ? null : _send)]))),
  ]));
}

class _LevelWavePainter extends CustomPainter {
  final List<double> levels; final Color color;
  _LevelWavePainter(this.levels, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 3..strokeCap = StrokeCap.round;
    final mid = size.height / 2;
    final n = levels.length;
    for (var i = 0; i < n; i++) {
      final x = n == 1 ? 0.0 : i * size.width / (n - 1);
      final h = 3 + levels[i] * (size.height - 3);
      canvas.drawLine(Offset(x, mid - h / 2), Offset(x, mid + h / 2), paint);
    }
  }
  @override bool shouldRepaint(covariant _LevelWavePainter oldDelegate) => true;
}
