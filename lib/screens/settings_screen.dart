import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../services/settings_store.dart';
import '../services/ai_assistant_service.dart';
import '../widgets/quick_assistant_fab.dart';
import 'niko_setup_screen.dart';

class SettingsScreen extends StatefulWidget { const SettingsScreen({super.key}); @override State<SettingsScreen> createState() => _SettingsScreenState(); }
class _SettingsScreenState extends State<SettingsScreen> {
  final _name = TextEditingController();
  @override void initState() { super.initState(); _name.text = SettingsStore.displayName; }
  @override void dispose() { _name.dispose(); super.dispose(); }
  Future<void> _saveName() async { if (_name.text.trim().isEmpty) return; await SettingsStore.saveProfile(firstName: _name.text.trim(), lastName: '', displayName: _name.text.trim()); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الاسم'))); }
  Future<void> _chooseSound(String id) async { await NotificationService.openChannelSettings(id); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر النغمة من إعدادات قناة Android ثم عد إلى التطبيق.'))); }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('الإعدادات')), floatingActionButton: const QuickAssistantFab(), body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
    const Padding(padding: EdgeInsets.fromLTRB(16, 18, 16, 6), child: Text('المظهر', style: TextStyle(fontWeight: FontWeight.bold))),
    RadioListTile<ThemeMode>(title: const Text('فاتح'), value: ThemeMode.light, groupValue: SettingsStore.themeMode.value, onChanged: (v) { if (v != null) SettingsStore.setThemeMode(v); setState(() {}); }),
    RadioListTile<ThemeMode>(title: const Text('داكن'), value: ThemeMode.dark, groupValue: SettingsStore.themeMode.value, onChanged: (v) { if (v != null) SettingsStore.setThemeMode(v); setState(() {}); }),
    RadioListTile<ThemeMode>(title: const Text('تلقائي حسب النظام'), value: ThemeMode.system, groupValue: SettingsStore.themeMode.value, onChanged: (v) { if (v != null) SettingsStore.setThemeMode(v); setState(() {}); }),
    const Divider(),
    const Padding(padding: EdgeInsets.fromLTRB(16, 14, 16, 6), child: Text('الملف الشخصي', style: TextStyle(fontWeight: FontWeight.bold))),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [Expanded(child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'اسم العرض'))), const SizedBox(width: 8), IconButton(onPressed: _saveName, icon: const Icon(Icons.save_outlined), tooltip: 'حفظ الاسم')])),
    const Divider(),
    const Padding(padding: EdgeInsets.fromLTRB(16, 14, 16, 6), child: Text('نيكو', style: TextStyle(fontWeight: FontWeight.bold))),
    ListTile(leading: Icon(AiAssistantService.isConfigured ? Icons.check_circle : Icons.warning_amber_outlined, color: AiAssistantService.isConfigured ? Colors.green : Colors.orange), title: const Text('إعداد اتصال نيكو'), subtitle: Text(AiAssistantService.isConfigured ? 'مهيأ للاختبار' : 'أضف المفتاح محليًا ثم اختبر الاتصال'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NikoSetupScreen()))),
    const Divider(),
    const Padding(padding: EdgeInsets.fromLTRB(16, 14, 16, 6), child: Text('نغمات الإشعارات', style: TextStyle(fontWeight: FontWeight.bold))),
    ListTile(leading: const Icon(Icons.play_arrow), title: const Text('بداية المهمة'), onTap: () => _chooseSound(kStartChannelId)),
    ListTile(leading: const Icon(Icons.flag_outlined), title: const Text('نهاية المهمة'), onTap: () => _chooseSound(kEndChannelId)),
    ListTile(leading: const Icon(Icons.snooze_outlined), title: const Text('المهمة المؤجلة'), onTap: () => _chooseSound(kSnoozeChannelId)),
    const Divider(),
    const ListTile(leading: Icon(Icons.info_outline), title: Text('قوة الآن 💪'), subtitle: Text('الإصدار V16 — حماية واستقرار ونيكو')),
  ]));
}
