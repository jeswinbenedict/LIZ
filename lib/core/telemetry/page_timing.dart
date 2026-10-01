/// Milliseconds since the browser started loading the page. Null outside the
/// web build.
library;

export 'page_timing_stub.dart'
    if (dart.library.js_interop) 'page_timing_web.dart';
