#!/usr/bin/env bash
# CI's app checks, run here the way CI runs them, before a push.
#
#     bash tool/ci_local.sh            # everything below
#     bash tool/ci_local.sh --fast     # skip the web build and browser checks
#
# Mirrors .github/workflows/ci.yml, jobs `flutter`, `scrapers` and `browser`:
# the same format check (lib, test *and* tool), analyze, tests, ruff and
# pytest, then a `flutter build web --release` (not --wasm: CI builds the
# default) checked by the same browser scripts in CI's timezone (UTC, see
# LIZ_TZ in tool/qa/common.py). Twice a push went red after passing here: a
# regex only CI's build exercised, and a page that laid out differently at
# night in UTC. Edge functions and migrations need Deno and Docker and are
# left to CI; they only change with supabase/.
#
# PYTHON names the interpreter with playwright, ruff and pytest installed
# (default: python). Stops at the first failure.

set -euo pipefail
cd "$(dirname "$0")/.."

PY="${PYTHON:-python}"
FAST=0
[ "${1:-}" = "--fast" ] && FAST=1
export LIZ_TZ="${LIZ_TZ:-UTC}"

step() { printf '\n== %s\n' "$*"; }

step "format (lib, test, tool)"
dart format --output=none --set-exit-if-changed lib test tool

step "analyze"
flutter analyze

step "test"
flutter test

step "ruff"
"$PY" -m ruff check scrapers tool --config scrapers/pyproject.toml

step "pytest"
"$PY" -m pytest scrapers/tests -q

if [ "$FAST" = 1 ]; then
  printf '\nFast checks passed (browser checks skipped).\n'
  exit 0
fi

step "build web (release, as CI)"
flutter build web --release

# The browser checks need the build served on 8100. Reuse a server that is
# already up; otherwise start one and stop it on the way out.
server=""
if ! curl -sf http://localhost:8100/ >/dev/null 2>&1; then
  "$PY" tool/qa/serve.py build/web 8100 >/dev/null 2>&1 &
  server=$!
  trap '[ -n "$server" ] && kill "$server" 2>/dev/null || true' EXIT
  for _ in $(seq 1 30); do
    curl -sf http://localhost:8100/ >/dev/null 2>&1 && break
    sleep 1
  done
fi

step "journeys (desktop)"
"$PY" tool/qa/journeys.py chromium
step "journeys (phone)"
"$PY" tool/qa/journeys.py chromium --phone
step "accessibility audit"
"$PY" tool/qa/a11y_audit.py
step "sweep"
"$PY" tool/qa/sweep.py chromium --key

printf '\nAll of CI'"'"'s app checks passed, in %s.\n' "$LIZ_TZ"
