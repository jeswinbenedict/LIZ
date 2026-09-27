import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Async provider for the shared preferences instance.
final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) {
  return SharedPreferences.getInstance();
});

/// App theme mode (system / light / dark), persisted across launches.
class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';
  SharedPreferences? _prefs;

  @override
  ThemeMode build() {
    // Read prefs if already loaded; otherwise start with system and update
    // once they arrive.
    _prefs = ref.watch(sharedPreferencesProvider).value;
    return _read(_prefs);
  }

  static ThemeMode _read(SharedPreferences? prefs) {
    switch (prefs?.getString(_key)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await _prefs?.setString(_key, mode.name);
  }

  void toggle() {
    set(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);
