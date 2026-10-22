import 'package:flutter/material.dart';
import '../services/settings_store.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _form = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _display = TextEditingController();
  bool _saving = false;

  @override
  void dispose() { _first.dispose(); _last.dispose(); _display.dispose(); super.dispose(); }

  Future<void> _continue() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final display = _display.text.trim().isEmpty ? '${_first.text.trim()} ${_last.text.trim()}'.trim() : _display.text.trim();
    await SettingsStore.saveProfile(firstName: _first.text.trim(), lastName: _last.text.trim(), displayName: display);
    await SettingsStore.setOnboardingComplete(true);
    if (mounted) Navigator.pushReplacementNamed(context, '/home');
  }

  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Form(key: _form, child: Column(children: [
    const Icon(Icons.fitness_center, size: 76, color: Color(0xFFC59D5F)),
    const SizedBox(height: 12),
    Text('قوة الآن 💪', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
    const SizedBox(height: 8), const Text('لنبدأ يومًا أكثر وضوحًا وإنجازًا.'), const SizedBox(height: 28),
    TextFormField(controller: _first, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'الاسم الأول', prefixIcon: Icon(Icons.person_outline)), validator: (v) => v == null || v.trim().isEmpty ? 'اكتب الاسم الأول' : null),
    const SizedBox(height: 12),
    TextFormField(controller: _last, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'اسم العائلة', prefixIcon: Icon(Icons.badge_outlined)), validator: (v) => v == null || v.trim().isEmpty ? 'اكتب اسم العائلة' : null),
    const SizedBox(height: 12),
    TextFormField(controller: _display, decoration: const InputDecoration(labelText: 'اسم العرض (اختياري)', prefixIcon: Icon(Icons.edit_outlined))),
    const SizedBox(height: 24), SizedBox(width: double.infinity, child: FilledButton(onPressed: _saving ? null : _continue, child: Text(_saving ? 'جارٍ الحفظ...' : 'متابعة'))),
  ]))))));
}
