import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;

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

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// Optional: base URL for calling Edge Functions ("Ask Liz", etc.). Falls back
  /// to the standard `<project>/functions/v1` path derived from [supabaseUrl].
  static const String functionsUrl = String.fromEnvironment(
    'FUNCTIONS_URL',
    defaultValue: '',
  );

  /// True when real Supabase credentials are present. Drives the repository
  /// layer's mock-vs-live selection.
  static bool get useSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static String get resolvedFunctionsUrl {
    if (functionsUrl.isNotEmpty) return functionsUrl;
    if (supabaseUrl.isEmpty) return '';
    return '$supabaseUrl/functions/v1';
  }

  /// Routes a third-party image through the CORS-friendly proxy.
  ///
  /// Flutter web fetches image *bytes*, so a host that sends no
  /// Access-Control-Allow-Origin (media.wired.com, for one) leaves the widget
  /// stuck on its placeholder forever. Native builds have no such restriction
  /// and fetch the original directly.
  /// [fallbackDomain] is a site the proxy can ask for a favicon when the
  /// stored image URL is dead. Product sites move their assets, and a logo
  /// scraped months ago is the thing that rots first — without a fallback the
  /// card silently drops to its initial tile and the proxy pays for the failed
  /// lookup on every view.
  static String proxiedImage(String url, {String? fallbackDomain}) {
    if (!kIsWeb) return url;
    final base = resolvedFunctionsUrl;
    if (base.isEmpty) return url;
    // Some logo_url values are already proxy links (/logo?domain=…). Wrapping
    // one again works but spends two function invocations to fetch one image.
    if (url.contains('/logo?')) return url;
    return buildProxyUrl(base, url, fallbackDomain: fallbackDomain);
  }

  /// The proxy URL itself, split out from the platform check so it can be
  /// exercised without a browser.
  @visibleForTesting
  static String buildProxyUrl(
    String base,
    String url, {
    String? fallbackDomain,
  }) {
    final domain = logoDomainOf(fallbackDomain);
    final suffix = domain == null
        ? ''
        : '&domain=${Uri.encodeComponent(domain)}';
    return '$base/logo?url=${Uri.encodeComponent(url)}$suffix';
  }

  static final RegExp _domainLike = RegExp(
    r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$',
    caseSensitive: false,
  );

  /// The bare host of [raw], or null if it has none to give.
  @visibleForTesting
  static String? logoDomainOf(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    var value = raw.trim();
    if (!value.contains('://')) value = 'https://$value';
    final host = Uri.tryParse(value)?.host;
    if (host == null || host.isEmpty) return null;
    final bare = host.startsWith('www.') ? host.substring(4) : host;
    // Uri accepts almost anything as a host — "not a url at all" parses with
    // the spaces escaped — so require something domain-shaped before handing
    // it to a favicon service.
    return _domainLike.hasMatch(bare) ? bare : null;
  }
}
