import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';

/// Records client-side crashes so a failure in front of a real user leaves a
/// trace somewhere.
///
/// Deliberately small: reports are fire-and-forget, never block a frame, and
/// never throw. A crash reporter that can itself crash, or that stalls the UI
/// while posting, is worse than none.
class CrashReporter {
  CrashReporter._();

  static const _maxReportsPerSession = 25;

  /// Which build crashed: the commit, stamped by the deploy workflow
  /// (`--dart-define=APP_VERSION=<sha>`). It used to be a fixed "1.0.0", so
  /// a report could not be matched to the source maps of the build that
  /// raised it (tool/symbolicate.py).
  static const _appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: 'dev',
  );

  static int _sent = 0;
  static final Set<String> _seen = <String>{};
  static String? _route;

  /// The screen the reader is on, recorded so a crash says where it happened.
  ///
  /// The three handlers below catch errors from anywhere in the app and have
  /// no idea which screen raised them, so every report went up with a null
  /// route — the first field anyone would look at. The router keeps this
  /// current instead.
  static set currentRoute(String? value) => _route = value;

  /// The signed-in person's Liz user id, set by the auth layer. Supabase's
  /// own `auth.currentUser` is unavailable now that sign-in is Firebase's.
  static String? userId;

  /// Installs the handlers and runs [body] inside a guarded zone.
  ///
  /// The three entry points catch different things: Flutter's own framework
  /// errors, errors the engine raises outside a widget callback, and anything
  /// escaping an async gap. Missing any one of them leaves a class of crash
  /// unrecorded.
  static Future<void> guard(FutureOr<void> Function() body) async {
    final flutterOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      flutterOnError?.call(details);
      report(details.exception, details.stack, context: {'source': 'flutter'});
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack, context: {'source': 'platform'});
      return true;
    };

    await runZonedGuarded(
      () async {
        await body();
      },
      (error, stack) {
        report(error, stack, context: {'source': 'zone'});
      },
    );
  }

  /// Groups repeats of the same fault. Line numbers move between builds, so the
  /// key is the error type plus the first few frames' symbols.
  static String fingerprintOf(Object error, StackTrace? stack) {
    final type = error.runtimeType.toString();
    final frames = (stack?.toString() ?? '')
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .take(3)
        .map((l) => l.replaceAll(RegExp(r'[:\d]+'), '').trim())
        .join('|');
    return sha256
        .convert(utf8.encode('$type::$frames'))
        .toString()
        .substring(0, 16);
  }

  static Future<void> report(
    Object error,
    StackTrace? stack, {
    Map<String, dynamic> context = const {},
    String? route,
  }) async {
    route ??= _route;
    // Always visible to a developer, whatever happens to the upload.
    if (kDebugMode) {
      debugPrint('CrashReporter: $error');
    }
    if (!Env.useSupabase) return;

    final fingerprint = fingerprintOf(error, stack);

    // One report per distinct fault per session, and a hard ceiling. A render
    // loop can raise the same error every frame; without this the client would
    // spend the session posting rows nobody needs.
    if (!_seen.add(fingerprint)) return;
    if (_sent >= _maxReportsPerSession) return;
    _sent++;

    try {
      final client = Supabase.instance.client;
      await client.from('error_events').insert({
        'message': error.toString().split('\n').first.trim(),
        'stack': stack?.toString(),
        'fingerprint': fingerprint,
        'route': route,
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'app_version': _appVersion,
        'user_id': userId,
        'context': context,
      });
    } catch (_) {
      // Reporting must never surface a second failure to the user.
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _sent = 0;
    _seen.clear();
    _route = null;
  }

  @visibleForTesting
  static String? get routeForTest => _route;

  @visibleForTesting
  static int get sentCount => _sent;
}
