import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/router.dart';
import 'app/settings_controller.dart';
import 'app/theme.dart';
import 'core/config/env.dart';
import 'core/firebase/firebase_app.dart';
import 'core/notifications/push_service.dart';
import 'core/telemetry/analytics.dart';
import 'core/telemetry/crash_reporter.dart';
import 'core/telemetry/page_timing.dart';
import 'core/providers.dart';
import 'shared/widgets/page_title.dart';

Future<void> main() async {
  // Everything runs inside the guard so a failure during startup is recorded
  // too — those are the ones a user is most likely to hit and least likely to
  // report.
  await CrashReporter.guard(() async {
    // Real paths (/tools/elevenlabs) rather than /#/tool/<id>: addresses a
    // person can read, and the precondition for pages a search engine can
    // index. The host must serve index.html for unknown paths.
    usePathUrlStrategy();
    // Pages opened with push (a tool, search, compare) put their own address
    // in the bar too, so refreshing, bookmarking or sharing the page keeps
    // the page. go_router leaves the old address there by default.
    GoRouter.optionURLReflectsImperativeAPIs = true;
    WidgetsFlutterBinding.ensureInitialized();

    // Initialize the live backend only when credentials are supplied via
    // --dart-define. Otherwise the app runs fully on bundled mock data.
    if (Env.useSupabase) {
      await Supabase.initialize(
        url: Env.supabaseUrl,
        // The same public key under the name Supabase now uses for it.
        publishableKey: Env.supabaseAnonKey,
        // Sign-in is Firebase's (migration 0055): every request carries the
        // Firebase ID token, or the public key for a guest.
        accessToken: firebaseIdToken,
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

/// Whether the accessibility tree is built from the start on the web.
///
/// Flutter web draws on a canvas and, by default, builds the tree a screen
/// reader reads only after someone finds and presses a hidden "Enable
/// accessibility" button — so a blind visitor met an empty page.
const _semanticsAtStart = bool.fromEnvironment('SEMANTICS', defaultValue: true);

class _LizAppState extends ConsumerState<LizApp> {
  SemanticsHandle? _semantics;

  @override
  void dispose() {
    _semantics?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (kIsWeb && _semanticsAtStart) {
      _semantics = SemanticsBinding.instance.ensureSemantics();
    }
    // Resume push after the first frame, for a browser that turned it on
    // before. Nobody is asked for permission here (see PushService).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      Analytics.firstFrame(millisSinceNavigation());
      final prefs = await ref.read(sharedPreferencesProvider.future);
      await PushService.instance.init(
        prefs: prefs,
        onToken: _persistToken,
        onOpen: _openRoute,
      );
    });
  }

  Future<void> _persistToken(String token, String platform) =>
      ref.read(authRepositoryProvider).registerDevice(token, platform);

  void _openRoute(String route) {
    if (route.startsWith('/')) ref.read(_routerProvider).go(route);
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(_routerProvider);

    // When the user signs in, link the cached device token to their account
    // (registerDevice no-ops while signed out, so this is when it takes effect).
    ref.listen(currentUserProvider, (prev, next) {
      if (prev == null && next != null) {
        PushService.instance.reregister(_persistToken);
      }
    });

    return MaterialApp.router(
      title: PageTitle.defaultTitle,
      debugShowCheckedModeBanner: false,
      // One theme: Signal, black and red (docs/DESIGN.md).
      theme: LizTheme.app(),
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}

/// The router is created once and kept alive for the app's lifetime.
final _routerProvider = Provider((ref) => buildRouter());
