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

The multi-threaded renderer needs them. **Decided 5 October 2026: the host
does not send them**, and Flutter uses the single-threaded renderer (still
WebAssembly, somewhat slower to draw). `Cross-Origin-Opener-Policy:
same-origin` severs a page from the windows it opens, and Google sign-in is a
Firebase popup (`signInWithPopup`): with the header, the popup could not hand
the sign-in back. Revisit only with a redirect-based sign-in, and then every
cross-origin resource the page embeds must allow embedding — logos come
through Liz's own proxy and fonts are bundled, so the Firebase Messaging
service worker is the likely risk.

## The deploy

`.github/workflows/deploy-web.yml` builds with `--wasm` (with the JavaScript
fallback) after CI passes on main, and daily, and publishes to Cloudflare
Pages (docs/OPERATIONS.md).
