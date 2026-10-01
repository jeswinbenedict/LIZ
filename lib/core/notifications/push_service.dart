import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase/firebase_app.dart';

/// Web push needs a VAPID key. Provide it at build time:
///   --dart-define=FCM_VAPID_KEY=...   (from Firebase → Cloud Messaging → Web Push certificates)
const _vapidKey = String.fromEnvironment('FCM_VAPID_KEY', defaultValue: '');

/// Background isolate handler. The OS renders "notification" messages itself;
/// this exists so background/terminated delivery is wired correctly.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // No-op: the system tray displays the notification.
}

/// FCM push, wrapped so the app runs perfectly whether or not Firebase is
/// configured. If Firebase/config is missing on this platform or build,
/// nothing throws and nothing breaks.
///
/// Permission is never asked on page load. The app used to call
/// requestPermission() after its first frame, so the first thing a new
/// visitor saw was a browser prompt from a site they had not used yet — which
/// people block on reflex and browsers penalise. Now [init] only resumes push
/// for a browser that already turned it on, and [enable] asks when someone
/// chooses "Turn on" in Alerts. Firebase itself is not even loaded until then.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  static const _prefKey = 'liz.push_enabled';

  bool _enabled = false;
  bool get enabled => _enabled;

  String? _token;
  String? get token => _token;

  Future<void> Function(String token, String platform)? _onToken;
  void Function(String route)? _onOpen;
  SharedPreferences? _prefs;
  bool _listening = false;

  String get _platform => kIsWeb ? 'web' : defaultTargetPlatform.name;

  /// Remembers how to persist a token and open a route, and resumes push if
  /// this browser turned it on before. Safe to call unconditionally.
  ///
  /// [onToken] persists the device token (e.g. to the `devices` table).
  /// [onOpen] receives a deep-link route from a tapped notification's data.
  Future<void> init({
    required SharedPreferences prefs,
    required Future<void> Function(String token, String platform) onToken,
    void Function(String route)? onOpen,
  }) async {
    _prefs = prefs;
    _onToken = onToken;
    _onOpen = onOpen;
    if (prefs.getBool(_prefKey) != true) return;
    await _register(ask: false);
  }

  /// Asks the browser for permission and registers this device. Returns
  /// whether notifications are now on. Call only from something the person
  /// chose to press.
  Future<bool> enable() async {
    await _register(ask: true);
    await _prefs?.setBool(_prefKey, _enabled);
    return _enabled;
  }

  Future<void> _register({required bool ask}) async {
    final onToken = _onToken;
    if (onToken == null) return;
    // Not configured → push disabled, app unaffected.
    if (!await ensureFirebase()) return;

    try {
      final messaging = FirebaseMessaging.instance;
      final settings = ask
          ? await messaging.requestPermission()
          : await messaging.getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return;
      }

      FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

      _token = await messaging.getToken(
        vapidKey: kIsWeb && _vapidKey.isNotEmpty ? _vapidKey : null,
      );
      _enabled = _token != null;
      if (_token != null) await onToken(_token!, _platform);

      if (_listening) return;
      _listening = true;
      messaging.onTokenRefresh.listen((t) {
        _token = t;
        onToken(t, _platform);
      });

      final onOpen = _onOpen;
      if (onOpen != null) {
        final initial = await messaging.getInitialMessage();
        _routeFrom(initial, onOpen);
        FirebaseMessaging.onMessageOpenedApp.listen(
          (m) => _routeFrom(m, onOpen),
        );
      }
    } catch (_) {
      // Any messaging error (e.g. missing web VAPID key) → stay disabled.
    }
  }

  void _routeFrom(RemoteMessage? m, void Function(String route) onOpen) {
    final r = m?.data['route'];
    if (r is String && r.isNotEmpty) onOpen(r);
  }

  /// Re-persist the cached token (e.g. right after sign-in, so it links to the
  /// now-known user).
  Future<void> reregister(
    Future<void> Function(String token, String platform) onToken,
  ) async {
    final t = _token;
    if (t != null) await onToken(t, _platform);
  }
}
