import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase web app config (public by design: it identifies the project, it
/// does not grant anything). Mobile would read its own config from
/// google-services.json / GoogleService-Info.plist.
const firebaseWebOptions = FirebaseOptions(
  apiKey: 'AIzaSyA9X8p7Bpg7DwRTRDUIz6VOjFKYvpUBB6w',
  authDomain: 'lizzy-50dc0.firebaseapp.com',
  projectId: 'lizzy-50dc0',
  storageBucket: 'lizzy-50dc0.firebasestorage.app',
  messagingSenderId: '828408834851',
  appId: '1:828408834851:web:4a36206ab71ff2af3e3a96',
  measurementId: 'G-VYG3P6976J',
);

Future<bool>? _starting;

/// Starts Firebase once, for push and for sign-in. False when it cannot
/// start (no config on this platform, a blocked script), so callers degrade
/// rather than throw.
///
/// Not called on page load for a guest: the Firebase SDK is fetched only when
/// someone signs in, turns on notifications, or comes back with a session —
/// a first-time visitor downloads none of it.
Future<bool> ensureFirebase() => _starting ??= _start();

Future<bool> _start() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: kIsWeb ? firebaseWebOptions : null);
    }
    return true;
  } catch (e) {
    debugPrint('Firebase did not start: $e');
    _starting = null;
    return false;
  }
}

/// True once Firebase has started in this run.
bool get firebaseStarted => Firebase.apps.isNotEmpty;

/// The signed-in person's Firebase ID token, for every Supabase request
/// (Supabase.initialize's `accessToken`). Null for a guest, which Supabase
/// treats as the anon key. The SDK refreshes the token when it is near
/// expiry, so this is cheap to call per request.
Future<String?> firebaseIdToken() async {
  if (!firebaseStarted) return null;
  try {
    return await FirebaseAuth.instance.currentUser?.getIdToken();
  } catch (_) {
    return null;
  }
}
