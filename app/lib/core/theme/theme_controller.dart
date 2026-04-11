import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists and exposes the user's [ThemeMode] preference.
///
/// Stored as an int in SharedPreferences:
///   0 = system, 1 = light, 2 = dark
class ThemeController extends ValueNotifier<ThemeMode> {
  static const _key = 'theme_mode';

  ThemeController() : super(ThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_key) ?? 0;
    value = ThemeMode.values[index.clamp(0, 2)];
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, mode.index);
  }

  String get label {
    switch (value) {
      case ThemeMode.system:
        return 'System';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }
}
