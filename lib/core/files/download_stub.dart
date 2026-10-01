import 'dart:typed_data';

/// Returns false: there is nowhere to save a file outside the browser build.
bool downloadBytes(Uint8List bytes, String filename, String mimeType) => false;
