import 'package:flutter/material.dart';
import '../screens/assistant_screen.dart';

class QuickAssistantFab extends StatelessWidget {
  const QuickAssistantFab({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'فتح نيكو العام',
    child: FloatingActionButton(
      heroTag: 'quick-niko',
      tooltip: 'نيكو العام',
      backgroundColor: const Color(0xFF126B50),
      foregroundColor: Colors.white,
      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AssistantScreen(mode: AssistantMode.general))),
      child: const Icon(Icons.auto_awesome),
    ),
  );
}
