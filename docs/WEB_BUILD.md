# The web build: JavaScript or WebAssembly

Evaluated on 27 September 2026 with Flutter 3.47.2, against the live project.

## Verdict

**Build with `--wasm` when Liz is deployed.** It compiles, it runs, and it
downloads about 30% less. It is a build flag rather than a rewrite: the output
carries both a WebAssembly and a JavaScript version, and Flutter's loader picks
WebAssembly where the browser supports it (WasmGC — current Chrome, Edge and
Firefox, and recent Safari) and falls back to JavaScript everywhere else.

```bash
flutter build web --release --wasm \
  --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…
```

`.claude/launch.json` has a `liz-web-wasm` configuration for trying it locally.

## What was checked

- **It compiles.** No package in the tree blocked it — Supabase, Firebase
  Messaging, shared_preferences, cached_network_image and go_router all build
  for WebAssembly. go_router 18 and cached_network_image 4 moved to
  `material_ui` precisely for this.
- **It runs.** In the browser, the page loaded `main.dart.wasm` and the
  `skwasm` renderer (confirmed from the resources the page fetched, not
  assumed), and Discover, Search, News with its Realtime badge, and proxied
  logos and images all worked against live data with no console errors.
- **It is smaller.** What a first visit downloads, gzipped:

  | | app code | renderer | total |
  |---|---|---|---|
  | JavaScript | `main.dart.js` 1.05 MB | `canvaskit.wasm` 2.92 MB | 3.97 MB |
  | WebAssembly | `main.dart.wasm` 1.21 MB | `skwasm.wasm` 1.54 MB | 2.76 MB |

  The app code is slightly larger as WebAssembly; the renderer is half the
  size, which is where the saving comes from.

## What the host has to do

The local check ran cross-origin isolated, because Flutter's development server
sends these headers:

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: credentialless
```

The multi-threaded renderer needs them. Decide at deployment whether the host
sends them, and test both ways there before relying on either:

- **With them**, every cross-origin resource the page embeds must allow it.
  Logos and images already come through Liz's own proxy with permissive CORS,
  and fonts are bundled, so the likely risk is the Firebase Messaging service
  worker and anything a future change embeds from elsewhere.
- **Without them**, Flutter uses the single-threaded renderer instead. Still
  WebAssembly, somewhat slower to draw.

## Not changed yet

The CI build and any deploy workflow belong to the deployment phase, which is
waiting on the choice of host. Nothing here changes how the app is built today.
