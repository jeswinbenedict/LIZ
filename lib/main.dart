import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/router.dart';
import 'app/settings_controller.dart';
import 'app/theme.dart';
import 'core/config/env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the live backend only when credentials are supplied via
  // --dart-define. Otherwise the app runs fully on bundled mock data.
  if (Env.useSupabase) {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
    );
  }

  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => prefs),
      ],
      child: const LizApp(),
    ),
  );
}

class LizApp extends ConsumerWidget {
  const LizApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final router = ref.watch(_routerProvider);

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
