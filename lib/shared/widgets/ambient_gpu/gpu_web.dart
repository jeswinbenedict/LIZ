import 'package:web/web.dart' as web;

/// Whether the browser gives Flutter a WebGL canvas. Without one (some
/// headless browsers, locked-down machines, old GPUs) Flutter draws on the
/// CPU, where a per-pixel shader for the whole screen costs seconds.
bool hasGpuCanvas() {
  try {
    final canvas =
        web.document.createElement('canvas') as web.HTMLCanvasElement;
    return canvas.getContext('webgl2') != null ||
        canvas.getContext('webgl') != null;
  } catch (_) {
    return false;
  }
}
