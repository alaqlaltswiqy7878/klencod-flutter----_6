import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'services/settings_store.dart';
import 'services/task_store.dart';
import 'services/notification_service.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  await SettingsStore.init();
  await TaskStore.init();
  try { await NotificationService.init(); } catch (_) {}
  runApp(const QuwatAlaanApp());
}

class QuwatAlaanApp extends StatelessWidget {
  const QuwatAlaanApp({super.key});
  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF126B50), brightness: brightness);
    return ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'sans', scaffoldBackgroundColor: dark ? const Color(0xFF101713) : const Color(0xFFF8F5EF), appBarTheme: AppBarTheme(centerTitle: true, elevation: 0, backgroundColor: dark ? const Color(0xFF173D2F) : const Color(0xFF126B50), foregroundColor: Colors.white), cardTheme: CardThemeData(elevation: 1.5, margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))), inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: dark ? const Color(0xFF1B251F) : Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)));
  }
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(valueListenable: SettingsStore.themeMode, builder: (_, mode, __) => MaterialApp(title: 'قوة الآن 💪', debugShowCheckedModeBanner: false, theme: _theme(Brightness.light), darkTheme: _theme(Brightness.dark), themeMode: mode, locale: const Locale('ar'), supportedLocales: const [Locale('ar'), Locale('en')], localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate], initialRoute: SettingsStore.onboardingComplete ? '/home' : '/onboarding', routes: {'/home': (_) => const HomeScreen(), '/onboarding': (_) => const OnboardingScreen()}));
}