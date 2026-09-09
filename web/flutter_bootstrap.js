// Custom bootstrap so the renderer is served from this origin.
//
// By default Flutter fetches CanvasKit — about 1.5 MB, and nothing paints
// until it arrives — from www.gstatic.com. That makes a Google CDN a hard
// dependency of the first screen: where it is slow, blocked, or having a bad
// day, Liz is down with it, and every visitor's browser announces itself to a
// third party before Liz has drawn a pixel. `flutter build web` already copies
// the same files into build/web/canvaskit, so pointing at them costs nothing
// and keeps the whole first load on one connection.

{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
  },
});
