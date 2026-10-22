import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsStore {
  static const String _darkKey = 'quwat_alaan_dark_mode';
  static const String _themeKey = 'quwat_alaan_theme_mode';
  static const String _onboardingKey = 'quwat_onboarding_complete';
  static const String _firstKey = 'quwat_profile_first_name';
  static const String _lastKey = 'quwat_profile_last_name';
  static const String _displayKey = 'quwat_profile_display_name';
  static const String _geminiKey = 'quwat_gemini_api_key';
  static final ValueNotifier<ThemeMode> themeMode = ValueNotifier<ThemeMode>(ThemeMode.light);
  static bool get isDark => themeMode.value == ThemeMode.dark;
  static bool get onboardingComplete => _onboardingComplete;
  static bool _onboardingComplete = false;
  static String get displayName => _displayName;
  static String _displayName = '';
  static String _geminiApiKey = '';
  static String get geminiApiKey => _geminiApiKey;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString(_themeKey);
    if (savedMode == 'system') themeMode.value = ThemeMode.system;
    else if (savedMode == 'dark' || (savedMode == null && (prefs.getBool(_darkKey) ?? false))) themeMode.value = ThemeMode.dark;
    else themeMode.value = ThemeMode.light;
    _onboardingComplete = prefs.getBool(_onboardingKey) ?? prefs.containsKey('quwat_alaan_tasks_data');
    _displayName = prefs.getString(_displayKey) ?? '';
    _geminiApiKey = prefs.getString(_geminiKey) ?? '';
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode.name);
    await prefs.setBool(_darkKey, mode == ThemeMode.dark); // توافق مع النسخ القديمة
  }

  static Future<void> setDarkMode(bool value) => setThemeMode(value ? ThemeMode.dark : ThemeMode.light);
  static Future<void> setOnboardingComplete(bool value) async { _onboardingComplete = value; final p = await SharedPreferences.getInstance(); await p.setBool(_onboardingKey, value); }
  static Future<void> saveProfile({required String firstName, required String lastName, required String displayName}) async { _displayName = displayName; final p = await SharedPreferences.getInstance(); await p.setString(_firstKey, firstName); await p.setString(_lastKey, lastName); await p.setString(_displayKey, displayName); }
  static Future<void> saveGeminiApiKey(String value) async { _geminiApiKey = value.trim(); final p = await SharedPreferences.getInstance(); await p.setString(_geminiKey, _geminiApiKey); }
  static Future<void> clearGeminiApiKey() async { _geminiApiKey = ''; final p = await SharedPreferences.getInstance(); await p.remove(_geminiKey); }
}
