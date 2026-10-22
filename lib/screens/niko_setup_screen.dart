import 'package:flutter/material.dart';
import '../services/ai_assistant_service.dart';
import '../services/settings_store.dart';

class NikoSetupScreen extends StatefulWidget {
  const NikoSetupScreen({super.key});
  @override State<NikoSetupScreen> createState() => _NikoSetupScreenState();
}

class _NikoSetupScreenState extends State<NikoSetupScreen> {
  final _key = TextEditingController();
  bool _hidden = true, _testing = false;
  String? _error;
  @override void initState() { super.initState(); _key.text = SettingsStore.geminiApiKey; }
  @override void dispose() { _key.dispose(); super.dispose(); }

  Future<void> _testAndSave() async {
    final candidate = AiAssistantService.sanitizeKey(_key.text);
    if (candidate.isEmpty) { setState(() => _error = 'أدخل مفتاح Gemini أولًا.'); return; }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() { _testing = true; _error = null; });
    try {
      await AiAssistantService.testConnection(apiKey: candidate);
      await SettingsStore.saveGeminiApiKey(candidate);
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم اختبار المفتاح وحفظه بنجاح'))); Navigator.pop(context, true); }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally { if (mounted) setState(() => _testing = false); }
  }

  Future<void> _clear() async { await SettingsStore.clearGeminiApiKey(); if (mounted) { _key.clear(); setState(() => _error = null); } }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إعداد نيكو')),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(24), children: [
      const Icon(Icons.auto_awesome, size: 72, color: Color(0xFFC59D5F)),
      const SizedBox(height: 16),
      Text(AiAssistantService.hasBuildKey ? 'المفتاح مدمج في التطبيق وقت البناء، ولا تحتاج لإدخاله هنا. يمكنك إدخال مفتاح آخر لتجاوزه.' : 'أدخل مفتاح Gemini. لن يُحفظ المفتاح إلا بعد نجاح اختبار اتصال حقيقي.'),
      const SizedBox(height: 8),
      Text(AiAssistantService.hasBuildKey ? 'حالة المفتاح المدمج: موجود ✅' : 'حالة المفتاح المدمج: غير موجود في هذا البناء ❌ (تأكد من GitHub Secret باسم GEMINI_API_KEY ثم أعد البناء)', style: const TextStyle(fontSize: 12)),
      const SizedBox(height: 18),
      TextField(controller: _key, obscureText: _hidden, autocorrect: false, enableSuggestions: false, decoration: InputDecoration(labelText: 'Gemini API Key', suffixIcon: IconButton(icon: Icon(_hidden ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _hidden = !_hidden)))),
      const SizedBox(height: 16),
      FilledButton.icon(onPressed: _testing ? null : _testAndSave, icon: _testing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_tethering), label: Text(_testing ? 'جارٍ الاختبار...' : 'اختبار الاتصال وحفظ المفتاح')),
      TextButton.icon(onPressed: _clear, icon: const Icon(Icons.delete_outline), label: const Text('حذف المفتاح من الهاتف')),
      if (_error != null) Card(color: Theme.of(context).colorScheme.errorContainer, child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!))),
    ])),
  );
}
