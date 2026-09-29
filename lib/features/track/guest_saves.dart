import 'package:shared_preferences/shared_preferences.dart';

/// Tools a visitor saved before signing in, kept in this browser.
///
/// Saving used to open the sign-in sheet, so the first thing Liz asked of a
/// new visitor was an account, before they had put anything into it. Now a
/// save works at once, and the list moves into the account on sign-in
/// (BookmarkController.fetch).
class GuestSaves {
  GuestSaves(this._prefs);
  final SharedPreferences _prefs;

  static const _key = 'liz.guest_saves';

  /// The most a browser keeps. A list is for tools someone means to come back
  /// to; this only stops a runaway loop filling storage.
  static const max = 200;

  Set<String> read() => (_prefs.getStringList(_key) ?? const []).toSet();

  /// Saves or unsaves [id]; returns whether it is now saved.
  Future<bool> toggle(String id) async {
    final ids = read();
    final added = !ids.remove(id);
    if (added) {
      if (ids.length >= max) return false;
      ids.add(id);
    }
    await _prefs.setStringList(_key, ids.toList());
    return added;
  }

  Future<void> clear() => _prefs.remove(_key);
}
