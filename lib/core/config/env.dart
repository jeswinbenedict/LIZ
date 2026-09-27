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

  /// Where Liz is served from, used to build shareable links to its own pages.
  ///
  /// Set it at build time for production. On the web the running origin is the
  /// right answer anyway, so this only matters for native builds, which have no
  /// address of their own to fall back on.
  static const String siteUrl = String.fromEnvironment(
    'SITE_URL',
    defaultValue: '',
  );

  /// The origin to hang a shared link off, or empty when there is none to give.
  static String get resolvedSiteUrl => siteUrl.isNotEmpty
      ? _normalizeBase(siteUrl)
      : (kIsWeb ? Uri.base.origin : '');

  /// A link to a tool's page on Liz, or null when Liz has no public address —
  /// better to share nothing than a link that goes nowhere.
  static String? toolPermalink(String toolId) =>
      permalinkFrom(resolvedSiteUrl, toolId);

  /// Split out from the platform lookup so the rules can be checked without a
  /// browser: no origin means no link, and a trailing slash never survives
  /// into one (two slashes look broken even when they resolve).
  ///
  /// The `#` is not decoration. The app routes on the URL fragment, so
  /// `<origin>/tool/<id>` loads the home screen and quietly drops the tool —
  /// a shared link that goes to the wrong place is worse than none. Moving to
  /// clean paths means teaching whatever serves the build to fall back to
  /// index.html, which is a deployment change, not a client one.
  @visibleForTesting
  static String? permalinkFrom(String base, String toolId) {
    final clean = _normalizeBase(base);
    if (clean.isEmpty || toolId.trim().isEmpty) return null;
    return '$clean/#/tool/$toolId';
  }

  static String _normalizeBase(String raw) =>
      raw.trim().replaceAll(RegExp(r'/+$'), '');

  /// True when real Supabase credentials are present. Drives the repository
  /// layer's mock-vs-live selection.
  static bool get useSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static String get resolvedFunctionsUrl {
    if (functionsUrl.isNotEmpty) return functionsUrl;
    if (supabaseUrl.isEmpty) return '';
    return '$supabaseUrl/functions/v1';
  }

  /// The origin the app is being served from, on web. Empty elsewhere.
  ///
  /// Uri.base is the page URL in a browser and the working directory on the
  /// VM, so the platform check is what keeps a test from producing a file://
  /// redirect.
  static String get currentOrigin {
    if (!kIsWeb) return '';
    try {
      return Uri.base.origin;
    } catch (_) {
      return '';
    }
  }

  /// Where a password-reset link should send the reader back to.
  ///
  /// Supabase appends the recovery token to this, and the SDK turns it into a
  /// session on arrival. It has to be an address Supabase is configured to
  /// allow (Authentication -> URL Configuration), or the link silently lands
  /// on the project's default site instead.
  ///
  /// Built from the running origin rather than hard-coded, so the same build
  /// works on localhost and on the deployed domain without a rebuild.
  static String get passwordResetRedirect {
    if (resetRedirectOverride.isNotEmpty) return resetRedirectOverride;
    final origin = currentOrigin;
    if (origin.isEmpty) return '';
    // Hash routing: the app reads /#/reset-password, and the token Supabase
    // appends survives in the query string ahead of it.
    return '$origin/#/reset-password';
  }

  static const resetRedirectOverride = String.fromEnvironment(
    'PASSWORD_RESET_REDIRECT',
  );

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

  /// A logo for a tool that has none stored, looked up by its site's domain.
  ///
  /// Null off the web, without a backend, or when the domain would give the
  /// wrong picture: every repository on github.com would get GitHub's mark, and
  /// every file on a shared host that host's — the same mistake as stamping a
  /// directory's logo on everything found there.
  static String? domainLogo(String? websiteUrl) {
    if (!kIsWeb) return null;
    final base = resolvedFunctionsUrl;
    if (base.isEmpty) return null;
    return buildDomainLogoUrl(base, websiteUrl);
  }

  @visibleForTesting
  static String? buildDomainLogoUrl(String base, String? websiteUrl) {
    final domain = logoDomainOf(websiteUrl);
    if (domain == null) return null;
    final shared = _sharedHosts.any(
      (host) => domain == host || domain.endsWith('.$host'),
    );
    if (shared) return null;
    return '$base/logo?domain=${Uri.encodeComponent(domain)}';
  }

  static const _sharedHosts = [
    'github.com',
    'githubusercontent.com',
    'producthunt.com',
    'ycombinator.com',
    'run.app',
    'google.com',
  ];

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
