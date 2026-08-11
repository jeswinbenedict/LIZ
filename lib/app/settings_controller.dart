import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Async provider for the shared preferences instance.
final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) {
  return SharedPreferences.getInstance();
});

/// App theme mode (system / light / dark), persisted across launches.
class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._prefs) : super(_read(_prefs));

  static const _key = 'theme_mode';
  final SharedPreferences? _prefs;

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

final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>((ref) {
  // Read prefs if already loaded; otherwise start with system and update later.
  final prefs = ref.watch(sharedPreferencesProvider).valueOrNull;
  return ThemeModeController(prefs);
});
