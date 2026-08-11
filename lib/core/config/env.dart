/// Compile-time environment configuration.
///
/// Values are injected at build/run time via `--dart-define`, e.g.:
///
/// ```
/// flutter run -d chrome \
///   --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi...
/// ```
///
/// When [supabaseUrl] / [supabaseAnonKey] are empty (the default), the app runs
/// in **mock mode**: every screen works against bundled sample data so the UI is
/// fully explorable with no backend. As soon as both values are provided the app
/// switches to the live Supabase backend automatically (see [useSupabase]).
///
/// NOTE: only the *anon* key ever belongs in the client. The service-role key
/// lives exclusively in n8n / Edge Functions and must never be defined here.
class Env {
  const Env._();

  static const String supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');

  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  /// Optional: base URL for calling Edge Functions ("Ask Liz", etc.). Falls back
  /// to the standard `<project>/functions/v1` path derived from [supabaseUrl].
  static const String functionsUrl =
      String.fromEnvironment('FUNCTIONS_URL', defaultValue: '');

  /// True when real Supabase credentials are present. Drives the repository
  /// layer's mock-vs-live selection.
  static bool get useSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static String get resolvedFunctionsUrl {
    if (functionsUrl.isNotEmpty) return functionsUrl;
    if (supabaseUrl.isEmpty) return '';
    return '$supabaseUrl/functions/v1';
  }
}
