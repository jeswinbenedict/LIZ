/// The app whose built-in browser is showing Liz, when it is one Google
/// refuses to sign in from ("disallowed_useragent"): links opened inside the
/// LinkedIn, Instagram or Facebook apps. Null in a real browser and outside
/// the web build.
library;

export 'in_app_browser_stub.dart'
    if (dart.library.js_interop) 'in_app_browser_web.dart';
