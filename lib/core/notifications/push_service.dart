import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Web push needs a VAPID key. Provide it at build time:
///   --dart-define=FCM_VAPID_KEY=...   (from Firebase → Cloud Messaging → Web Push certificates)
const _vapidKey = String.fromEnvironment('FCM_VAPID_KEY', defaultValue: '');

/// Firebase web app config (public by design). Mobile reads its own config from
/// google-services.json / GoogleService-Info.plist instead, so this is web-only.
const _webOptions = FirebaseOptions(
  apiKey: 'AIzaSyA9X8p7Bpg7DwRTRDUIz6VOjFKYvpUBB6w',
  authDomain: 'lizzy-50dc0.firebaseapp.com',
  projectId: 'lizzy-50dc0',
  storageBucket: 'lizzy-50dc0.firebasestorage.app',
  messagingSenderId: '828408834851',
  appId: '1:828408834851:web:4a36206ab71ff2af3e3a96',
  measurementId: 'G-VYG3P6976J',
);

/// Background isolate handler. The OS renders "notification" messages itself;
/// this exists so background/terminated delivery is wired correctly.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // No-op: the system tray displays the notification.
}

/// FCM push, wrapped so the app runs perfectly whether or not Firebase is
/// configured. If Firebase/config is missing on this platform or build,
/// [init] simply disables push and returns — nothing throws, nothing breaks.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  bool _enabled = false;
  bool get enabled => _enabled;

  String? _token;
  String? get token => _token;

  String get _platform => kIsWeb ? 'web' : defaultTargetPlatform.name;

  /// Initializes Firebase Messaging. Safe to call unconditionally.
  ///
  /// [onToken] persists the device token (e.g. to the `devices` table).
  /// [onOpen] receives a deep-link route from a tapped notification's data.
  Future<void> init({
    required Future<void> Function(String token, String platform) onToken,
    void Function(String route)? onOpen,
  }) async {
    try {
      // Web needs options passed explicitly; mobile reads them from its native
      // config file (google-services.json / GoogleService-Info.plist). Throws if
      // absent — caught below to keep push optional.
      await Firebase.initializeApp(options: kIsWeb ? _webOptions : null);
    } catch (_) {
      return; // Not configured → push disabled, app unaffected.
    }

    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

      _token = await messaging.getToken(
        vapidKey: kIsWeb && _vapidKey.isNotEmpty ? _vapidKey : null,
      );
      _enabled = _token != null;
      if (_token != null) await onToken(_token!, _platform);

      messaging.onTokenRefresh.listen((t) {
        _token = t;
        onToken(t, _platform);
      });

      if (onOpen != null) {
        final initial = await messaging.getInitialMessage();
        _routeFrom(initial, onOpen);
        FirebaseMessaging.onMessageOpenedApp
            .listen((m) => _routeFrom(m, onOpen));
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
      Future<void> Function(String token, String platform) onToken) async {
    final t = _token;
    if (t != null) await onToken(t, _platform);
  }
}
