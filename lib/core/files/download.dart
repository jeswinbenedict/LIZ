/// Saves bytes as a file the person downloads. Web only; elsewhere it reports
/// that it cannot (there is no native build today).
library;

export 'download_stub.dart' if (dart.library.js_interop) 'download_web.dart';
