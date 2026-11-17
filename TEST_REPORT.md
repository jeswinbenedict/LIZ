# Test report

Tests run on 17 November 2026, during the audit that followed making the
repository public ([SECURITY_AUDIT.md](SECURITY_AUDIT.md)). Every result
below was observed in this session; nothing is estimated. Results are for
commit `8d72882` and the follow-up fix described at the end.

## Summary

| Suite | Command | Result |
| --- | --- | --- |
| Formatting | `dart format --output=none --set-exit-if-changed lib test tool` | 200 files, 0 changed |
| Static analysis | `flutter analyze` (infos fatal) | No issues |
| Flutter unit, widget and accessibility tests | `flutter test` | **454 passed**, 0 failed |
| Python lint | `ruff check scrapers tool --config scrapers/pyproject.toml` | No issues |
| Scraper tests | `cd scrapers && python -m pytest tests` | **161 passed**, 0 failed |
| Edge Function tests | `deno test --allow-env --no-check supabase/functions/tests` | **144 passed**, 0 failed |
| Edge Function type check | `deno check supabase/functions/<fn>/index.ts` | All changed functions pass |
| Production build | `flutter build web --release` | Succeeds |
| Browser journeys, desktop | `tool/qa/journeys.py` (1440 px, Chromium) | **14/14 passed** |
| Browser journeys, phone | `tool/qa/journeys.py` (390 px, Chromium) | **14/14 passed** |
| Accessibility audit | `tool/qa/a11y_audit.py` | **0 findings** |
| Page sweep (errors, overflow) | `tool/qa/sweep.py` | Passed |
| Migrations on a fresh database, schema and RLS checks | CI job `migrations` | Passed (GitHub) |
| Secret scan | gitleaks, CI job `security` | No findings (GitHub) |
| Dependency vulnerabilities | OSV-Scanner on `pubspec.lock`, `scrapers/requirements.txt` | None known (GitHub) |
| Static security analysis | CodeQL (Actions, JavaScript/TypeScript, Python) | 7 alerts: 5 fixed, 2 dismissed with reasons |
| Live backend, signed-out | `python tool/qa/probe_live.py` | **0 failures** (14 functions, 33 tables and views) |
| Live site | Browser, `https://liz-cfp.pages.dev` | Starts; security headers present |

The local run was `bash tool/ci_local.sh`, which runs formatting, analysis,
Flutter tests, ruff, pytest, the release build, both journey widths, the
accessibility audit and the sweep. On GitHub, CI run `44126129319` passed
every job: `flutter`, `scrapers`, `edge-functions`, `migrations`, `browser`,
`security`, `changes`. Both deploys that followed (`deploy-web`
`44128028545`, `deploy-supabase` `44128028821`) succeeded.

## What the suites cover

- **Authentication.** Sign-in and sign-up validation, password reset, session
  expiry and recovery, the auth gate and its redirect target, Firebase token
  handling, two-step verification for admins
  (`test/sign_in_validation_test.dart`, `password_reset_test.dart`,
  `session_expiry_test.dart`, `auth_gate_test.dart`,
  `firebase_auth_test.dart`, `two_step_gate_test.dart`, and
  `supabase/functions/tests/firebase_auth_test.ts`, `signed_in_test.ts`,
  `auth_test.ts`).
- **Authorization.** Service-role-only functions refuse other keys
  (`auth_test.ts`); signed-in users cannot change protected columns such as
  their own role (CI `migrations` job, against a real Postgres); every table's
  RLS and every function's refusal, live (`probe_live.py`).
- **Database.** Every migration applied in order to a fresh Supabase database,
  the schema checked against what the app expects (CI `migrations`).
- **APIs.** Each Edge Function's decisions are tested through its `logic.ts`
  without network: ingestion, summaries, AI fallback, rate limits, news,
  logos, tool updates, Repository Analyzer.
- **User journeys** in a real browser on demo data: Discover filters, opening
  a tool, search and Cmd-K, Ask Liz, compare, save, not-found recovery, news
  links, keyboard-only navigation, category pages.
- **Responsive and accessible UI.** `test/screen_sweep_test.dart` puts every
  screen, signed in and out, through a 320 px phone, 1.5x text, a tablet in
  portrait and Flutter's accessibility guidelines.
- **Security regressions** added in this audit:
  `supabase/functions/tests/hardening_test.ts` (generic error replies,
  linear-time citation parsing, no stray angle brackets, single unescaping)
  and `scrapers/tests/test_feed_nav.py` (linear-time tagline cleanup).

## Live backend probe

`tool/qa/probe_live.py` against production, with no credentials and with the
public anon key, empty bodies only:

- 14 of 14 Edge Functions refuse: 401, or 400 for an empty body
  (`ask-liz`, `logo`, `tool-updates`). A real question to `ask-liz` without a
  session returns 401.
- 33 of 33 tables and views return no rows to the anon key, or refuse
  (`collections` and `drops` no longer exist and answer 404).

## Not run, and why

| Test | Reason |
| --- | --- |
| Sign-up, sign-in, sign-out, password reset and account deletion **against production** | They create accounts and need passwords on the live service. They are covered on demo data and in unit tests; a manual pass with a test account is listed in PRODUCTION_READINESS.md. |
| Local Supabase integration run | Docker was not running on the audit machine. The same migrations and policy checks ran in CI's `migrations` job against a real database. |
| `python -m liz_scraper.eval_ask` (Ask Liz, 60 questions) | Calls the live model and spends its quota; not part of CI by design. |
| Native Android and iOS | Not built: the project is web only (README, "Deliberate decisions"). |
| Browsers other than Chromium | CI runs Chromium. `tool/qa` supports Edge, Firefox and WebKit locally; not run in this session. |
| File uploads (avatar via `image_picker`) | No automated test drives the platform file picker; not exercised in this session. |
| Push notifications end to end | Needs a browser with granted permission and a real device token. |
| Performance under load | No load test exists; rate limits are unit-tested. |

## Follow-up

CodeQL's re-scan of `8d72882` still found three error replies outside the
first fix (`fetch-news`, `scraper-ingest`, `tool-updates`); they now use the
same `failure()` helper. After that change: Edge Function tests 144 passed,
the three functions type-check. Its CI result is recorded on GitHub with the
commit that adds this report.

No test failed in any run recorded here.
