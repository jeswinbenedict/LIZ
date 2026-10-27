# Browser checks

Widget tests prove the Dart code; these prove the app in a real browser —
where the address bar, keyboard focus, and what a screen reader is given all
live, and where each of them has broken without a single widget test failing.

| Script | What it checks |
|---|---|
| `journeys.py` | 13 visitor journeys, step by step: open a mover (and reload, and go Back), search, ⌘K, Ask Liz, compare, save as a guest, sign-in validation, forgot password, the 404 page, news links, keyboard only, a category page |
| `a11y_audit.py` | Every page's accessibility tree: a level-1 heading, no unnamed controls, no repeated names, links with addresses |
| `sweep.py` | Every page at four widths: uncaught errors, failed requests, horizontal overflow, time to first frame, a screenshot of each |
| `serve.py` | Serves a web build the way the host does (index.html for unknown paths), for CI |

The pages visited are discovered from Discover, so the same scripts run
against the live catalog and against the demo data CI builds.

## Before a push: all of CI's app checks

```bash
PYTHON=~/.liz/scraper-venv/Scripts/python.exe bash tool/ci_local.sh
```

`tool/ci_local.sh` runs what CI's `flutter`, `scrapers` and `browser` jobs
run, the way they run it: the format check over `lib`, `test` and `tool`,
analyze, the tests, ruff and pytest, a `flutter build web --release` (not
`--wasm`), and these scripts — in UTC, CI's timezone. The pages take their
clock from `LIZ_TZ` (default `UTC`, in `common.py`): News groups stories by
day, and once laid out differently at night in UTC than here, so a check
passed locally and failed in CI. `--fast` stops before the build.

## Running them

Once:

```bash
pip install playwright==1.63.0
```

```bash
python -m playwright install chromium firefox webkit
```

Against a release build on `localhost:8100` (the `liz-web-release` launch
configuration, or `flutter run --release -d web-server --web-port 8100
--web-hostname localhost` with the Supabase defines):

```bash
python tool/qa/journeys.py chromium
```

```bash
python tool/qa/a11y_audit.py
```

```bash
python tool/qa/sweep.py chromium
```

Each takes an engine — `chromium`, `msedge`, `firefox` or `webkit` — and
`journeys.py` and `a11y_audit.py` take `--phone` for a 390 px window. Point
them elsewhere with `LIZ_URL`. Screenshots and the sweep's JSON go to
`liz-qa` in the system temp folder (`LIZ_QA_OUT` to change it).

Use `localhost`, not `127.0.0.1`: Firebase authorises the former only.

## When a journey fails

Look at its screenshot before changing anything. Half the failures while
these were written were the script's, not the app's — a selector, or acting
before an animation finished — and the comments in `journeys.py` record the
waits that came out of them. The other half were real: the address bar not
following the page, controls the keyboard could not reach, headings that
swallowed their sections.
