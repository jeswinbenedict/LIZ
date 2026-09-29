# Liz

**Discover the next big AI tool before everyone else.**

Liz is a web application for finding AI tools while they are still rising. It
collects new launches from Product Hunt, Hacker News and GitHub, decides which
are worth showing, summarises them, and lets people search in plain language,
follow the ones they care about, and hear when something changes.

Built with Flutter for the web, backed by Supabase. Every AI feature runs on
free and open models: search uses `gte-small` embeddings computed inside
Supabase, and summaries use open-source models on Groq's free tier.

---

## Run it

### With bundled demo data — no setup

```bash
flutter pub get
flutter run -d chrome
```

With no Supabase credentials the app uses a bundled dataset and a mock backend,
so every screen works offline. Sign in with any email and password: the demo
account is an admin, so the admin console is reachable too.

### Against the live backend

```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key>
```

With both values present the app switches to live data automatically. Only the
anon key belongs in the client — it is public by design and every table is
protected by row-level security. `.claude/launch.json` has both configurations.

---

## What is in here

```
lib/                Flutter web app
  app/              router, theme, responsive shell
  core/             auth, config, repositories (mock + Supabase), telemetry
  features/         discover, search, ask_liz, tool_detail, news, alerts,
                    track (saved, follow), compare, profile, auth, admin,
                    community (built, hidden from navigation — see below)
  shared/           models and widgets
supabase/
  migrations/       schema, RLS, triggers, cron jobs, health checks
  functions/        Edge Functions (Deno) and their tests
scrapers/           Python/BeautifulSoup scraper, quality gate, backlog tools
n8n/                workflow for running the scraper from your own machine
docs/               how the pieces work — start here
test/               Flutter tests
```

## How the catalog fills itself

Scheduled jobs inside Supabase fetch GitHub tools daily and news hourly,
compute embeddings and summaries every fifteen minutes, and refresh rankings.
The Python scraper finds Product Hunt and Hacker News launches, follows each
listing to the product's own site, and a **quality gate** decides whether the
result is fit to publish. Anything held back keeps a recorded reason, visible in
the admin console.

→ [docs/CATALOG_PIPELINE.md](docs/CATALOG_PIPELINE.md)

Product Hunt blocks datacenter addresses, so its launches only resolve when the
scraper runs from a home connection. That is what the n8n workflow is for.

→ [n8n/README.md](n8n/README.md)

## How "Rising" is decided

Every tool's GitHub stars, Hacker News points, and views, website visits and
saves on Liz are recorded daily, and tools are ranked by how much those grew in
the last seven days — with the reason shown in words ("227 points on Hacker
News"). A famous tool that is not growing is not rising. Nothing shown is
estimated or seeded.

→ [docs/RANKING.md](docs/RANKING.md)

## Knowing it still works

`system_health()` reports twelve signals derived from the data itself — catalog
and news freshness, embedding and summary coverage, unexplained backlog, failed
scheduled calls, crash reports, open reports, and whether the daily signal
history and outside signals are still being written. It runs hourly and notifies admins
when something fails, at most once every six hours. The admin console's
**Health** tab shows all of it.

## Security

What is protected, how it was checked, and what was found — including the
problems fixed along the way.

→ [docs/SECURITY.md](docs/SECURITY.md)

## Tests

```bash
flutter analyze                                           # clean at every level
flutter test                                              # app
cd scrapers && python -m pytest tests                     # scraper
cd scrapers && python -m liz_scraper.eval_ask              # Ask Liz, 60 questions (live)
deno test --allow-env --no-check supabase/functions/tests # Edge Functions
```

All three run in CI on every push, and `flutter analyze` fails on infos too.
Beyond behaviour, `test/screen_sweep_test.dart` puts every screen, signed out
and signed in, through a 320-pixel phone, 1.5× text and a tablet, and through
Flutter's accessibility guidelines — labelled controls, 48-pixel tap targets
and contrast in light and dark. A new screen goes in that list. Every Edge
Function has tests; their decisions live in `logic.ts` files so the tests need
no network.

---

## Deliberate decisions

- **Web only.** The Android and iOS scaffolds were removed rather than carried
  unbuilt. `flutter create --platforms android,ios .` restores them; re-enable
  the platform keys in `pubspec.yaml` for icons and splash at the same time.
- **Community is built but hidden.** Posts, comments and their moderation work
  and are tested, but an empty forum reads worse to a first-time visitor than no
  tab at all. Adding it back is one entry in `kNavDestinations`. Reviews on tool
  pages are separate and live.
- **No paid AI APIs.** Semantic search is embeddings in the database; summaries
  use free open models.

## Privacy and terms

Both live in the app at `/privacy` and `/terms` (`lib/features/legal/`), linked
from Settings and from sign-up. The privacy policy describes what the schema and
Edge Functions actually store, and for how long — change one, change the other.
Build with `--dart-define=LEGAL_CONTACT=you@example.com` to publish a contact
address in both; without it they point to account deletion and Report instead.
They were written from the code, not by a lawyer.

## Still to do

- **Email delivery.** No SMTP provider is configured, so password-reset links,
  magic links and confirmation emails are built and tested but cannot be sent.
- **Google and Apple sign-in** need OAuth credentials; only email works today.
- **A contact address** for the privacy policy and terms (`LEGAL_CONTACT`), and
  a legal read of both before launch.
- **Deployment.** No host is configured yet, `site_url` still points at
  `localhost:3000`, and URLs use `/#/` rather than clean paths. Build with
  `--wasm` when it happens: evaluated, working and 30% smaller →
  [docs/WEB_BUILD.md](docs/WEB_BUILD.md).
  `toolBySlug()` is kept for the per-tool URLs that work will add.
