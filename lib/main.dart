import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/router.dart';
import 'app/settings_controller.dart';
import 'app/theme.dart';
import 'core/config/env.dart';
import 'core/notifications/push_service.dart';
import 'core/telemetry/analytics.dart';
import 'core/telemetry/crash_reporter.dart';
import 'core/providers.dart';

Future<void> main() async {
  // Everything runs inside the guard so a failure during startup is recorded
  // too — those are the ones a user is most likely to hit and least likely to
  // report.
  await CrashReporter.guard(() async {
    // Real paths (/tools/elevenlabs) rather than /#/tool/<id>: addresses a
    // person can read, and the precondition for pages a search engine can
    // index. The host must serve index.html for unknown paths.
    usePathUrlStrategy();
    WidgetsFlutterBinding.ensureInitialized();

    // Initialize the live backend only when credentials are supplied via
    // --dart-define. Otherwise the app runs fully on bundled mock data.
    if (Env.useSupabase) {
      await Supabase.initialize(
        url: Env.supabaseUrl,
        // The same public key under the name Supabase now uses for it.
        publishableKey: Env.supabaseAnonKey,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    Analytics.init(prefs);

    runApp(
      ProviderScope(
        // Riverpod 3 retries a failed provider up to ten times with backoff.
        // Liz's failures are mostly ones a retry cannot fix — a row-level
        // security refusal, an expired session — and every screen already
        // shows its error with a Retry button, so errors surface at once.
        retry: (retryCount, error) => null,
        overrides: [sharedPreferencesProvider.overrideWith((ref) => prefs)],
        child: const LizApp(),
      ),
    );
  });
}

class LizApp extends ConsumerStatefulWidget {
  const LizApp({super.key});

  @override
  ConsumerState<LizApp> createState() => _LizAppState();
}

class _LizAppState extends ConsumerState<LizApp> {
  @override
  void initState() {
    super.initState();
    // Kick off push registration after first frame. Fully guarded: if Firebase
    // isn't configured on this platform/build, it silently no-ops.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PushService.instance.init(onToken: _persistToken, onOpen: _openRoute);
    });
  }

  Future<void> _persistToken(String token, String platform) =>
      ref.read(authRepositoryProvider).registerDevice(token, platform);

  void _openRoute(String route) {
    if (route.startsWith('/')) ref.read(_routerProvider).go(route);
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final router = ref.watch(_routerProvider);

    // When the user signs in, link the cached device token to their account
    // (registerDevice no-ops while signed out, so this is when it takes effect).
    ref.listen(currentUserProvider, (prev, next) {
      if (prev == null && next != null) {
        PushService.instance.reregister(_persistToken);
      }
    });

    return MaterialApp.router(
      title: 'Liz',
      debugShowCheckedModeBanner: false,
      theme: LizTheme.light(),
      darkTheme: LizTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}

/// The router is created once and kept alive for the app's lifetime.
final _routerProvider = Provider((ref) => buildRouter());
