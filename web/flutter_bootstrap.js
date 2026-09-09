// Custom bootstrap so the renderer is served from this origin.
//
// By default Flutter fetches CanvasKit — about 5 MB, and nothing paints until
// it arrives — from www.gstatic.com. That makes a Google CDN a hard dependency
// of the first screen: where it is slow, blocked, or having a bad day, Liz is
// down with it, and every visitor's browser announces itself to a third party
// before Liz has drawn a pixel. `flutter build web` already copies the same
// files into the build, so pointing at them costs nothing and keeps the whole
// first load on one connection.
//
// Everything else here matches what Flutter generates by default. The service
// worker settings in particular must stay: without them nothing registers the
// worker, and every repeat visit re-downloads the whole app.

{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
  },
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
});
