# Liz

**Discover the next big AI tool before everyone else.**

Liz is an AI & technology discovery platform — one Flutter codebase shipping to
**Web, iOS, and Android**, backed by Supabase. Find new and rising tools early,
compare them, track them, and share honest community reviews.

This repo contains the Phase 1 MVP: a fully responsive Flutter app plus the
Supabase backend (schema, RLS, triggers, seed, Edge Functions) and n8n ingestion
notes.

---

## Run it right now (no backend needed)

The app ships with a rich bundled dataset, so it runs and is fully explorable
with **zero configuration** — "demo mode".

```bash
flutter pub get
flutter run -d chrome
```

Everything works against local mock data: Discover / Rising Early / Trending,
search, tool detail, Ask Liz, community posts & reviews, bookmarks, compare,
profile, settings, and the admin panel (the demo user is an admin). Sign-in shows
a **"continue as demo user"** shortcut.

Resize the window from ~320px to desktop to see the adaptive shell morph:
**bottom nav → nav rail → sidebar**.

---

## Project layout

```
lib/
  app/            router (go_router), theme, responsive shell + breakpoints
  core/
    config/       env (SUPABASE_URL / ANON_KEY via --dart-define)
    auth/         AuthRepository: mock + Supabase implementations
    data/         bundled mock dataset (24 tools + reviews/posts/news)
    repository/   Content/Community/Track/Admin repos: mock + Supabase
    providers.dart  Riverpod wiring — picks mock vs Supabase from Env.useSupabase
  features/       discover, tool_detail, compare, community, reviews, track,
                  ask_liz, auth, profile, admin
  shared/         models, reusable widgets (cards, badges, states, avatars)
supabase/
  migrations/     0001 schema · 0002 RLS · 0003 functions/triggers
  seed.sql        categories + 24 tools + news (safe to re-run)
  seed_community.sql  starter reviews/posts (needs real user UUIDs — template)
  functions/      ask-liz · summarize · report · delete-account (Deno/TS)
  config.toml     local dev config
n8n/README.md     ingestion pipeline (sources → normalize → dedupe → AI → Supabase)
```

The repository layer is **backend-agnostic**: features talk to interfaces, and
`providers.dart` swaps in the Supabase implementation automatically once
credentials are present.

---

## Connect the real backend (Supabase)

### 1. Create the project & install the CLI

- Create a project at [supabase.com](https://supabase.com) (or run locally).
- Install the CLI: `npm i -g supabase` (or `scoop install supabase`).

### 2. Apply the schema, policies, and seed

```bash
supabase link --project-ref <your-project-ref>
supabase db push          # applies migrations/0001..0003
supabase db execute --file supabase/seed.sql
```

Local alternative (Docker): `supabase start` then `supabase db reset` (runs
migrations + `seed.sql` automatically).

### 3. Configure auth providers

In the dashboard (Authentication → Providers) enable **Email**, **Google**, and
**Apple** (Apple is required on iOS if any social login is offered). Add redirect
URLs including your app scheme (see `supabase/config.toml`).

### 4. Deploy the Edge Functions & set secrets

```bash
supabase functions deploy ask-liz summarize report delete-account
# AI (summaries + Ask Liz) uses a FREE, OpenAI-compatible provider — Groq by
# default (open-source Llama models). Get a free key at console.groq.com:
supabase secrets set AI_API_KEY=gsk_...                # server-side only
# Optional overrides to switch providers (all OpenAI-compatible):
#   Groq (default):  AI_BASE_URL=https://api.groq.com/openai/v1  AI_MODEL=llama-3.3-70b-versatile
#   OpenRouter:      AI_BASE_URL=https://openrouter.ai/api/v1    AI_MODEL=meta-llama/llama-3.3-70b-instruct:free
#   Gemini:          AI_BASE_URL=https://generativelanguage.googleapis.com/v1beta/openai  AI_MODEL=gemini-2.0-flash
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are injected
into functions by the platform automatically.

### 5. (Optional) Seed starter community content

Create 2–3 users (dashboard or via the app), then edit the UUIDs in
`supabase/seed_community.sql` and run it — so the community isn't an empty room.

### 6. Point the app at Supabase

Only the **anon** key belongs in the client. The service-role key stays in
n8n / Edge Functions.

```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key>
```

With both defines present the app switches from mock to live data automatically.

---

## Content ingestion (n8n)

See [`n8n/README.md`](n8n/README.md). n8n pulls from APIs (Product Hunt, GitHub,
Hacker News) and RSS on a schedule, dedupes via `content_hash`, enriches with the
`/summarize` function, and upserts into Supabase with `status = 'pending'` for
admin review. The Flutter app never scrapes.

Schedule `select refresh_trend_scores();` nightly to update trend / "Rising Early"
rankings.

---

## Technology News Feed

The **News** tab shows live technology headlines, updated continuously — all from
**free, open-source** sources.

**How content arrives:**
1. The [`fetch-news`](supabase/functions/fetch-news/index.ts) Edge Function pulls the
   latest tech news from:
   - **RSS/Atom feeds** (open standard): TechCrunch, The Verge, Ars Technica, Wired,
     Engadget, VentureBeat, and Hacker News (via `hnrss.org`).
   - The **Dev.to** public API (free, no key).
   - A **`deno-dom` scraping fallback** (`scrapeHeadlines`) for sources without a feed.
     For JS-heavy sites that need a real browser, point a **Playwright/Cheerio** worker
     (n8n or a small VPS) at the same `news` table.
   It normalizes, dedupes by URL, and upserts — safe to run repeatedly.
2. It runs **hourly** via a free **GitHub Actions** cron
   ([`.github/workflows/fetch-news.yml`](.github/workflows/fetch-news.yml)), or via the
   `pg_cron` template in [`0004_news_realtime.sql`](supabase/migrations/0004_news_realtime.sql).
3. New rows are pushed to the app **in real time** via **Supabase Realtime** — the feed
   shows a **LIVE** badge and prepends articles as they land.

**Set it up:**
```bash
supabase functions deploy fetch-news
supabase functions invoke fetch-news    # one-time backfill
```
Then add repo secrets `SUPABASE_FUNCTIONS_URL` and `SUPABASE_ANON_KEY` in GitHub
(Settings → Secrets → Actions) and the hourly job runs itself. Optionally set
a free `AI_API_KEY` (Groq/OpenRouter/Gemini) to attach 3-bullet AI "quick takes" per article.

> Liz shows a **snippet + link out** to the original source — it never republishes full
> articles.

## Build targets

```bash
flutter build web        # → build/web  (host on Cloudflare Pages / Vercel / Netlify)
flutter build appbundle  # Android
flutter build ipa        # iOS (Apple Sign-In + privacy manifest + delete-account required)
```

Pass the same `--dart-define` values shown above to production builds.

---

## Security & production notes

- **RLS on every table**, deny-by-default; users edit only their own content;
  moderators/admins can hide/remove any content (see `0002_rls.sql`).
- **Service-role key never ships to the client** — server-side only.
- **Moderation from day one**: report button → `handle_report` trigger auto-hides
  at 3 reports → admin review queue.
- **Delete-account flow** (`/delete-account` function) for App Store compliance.
- Enable Supabase automated backups; wire up Sentry + analytics before launch.

## Status

Phase 1 (MVP) is implemented. Phase 2 (full "Rising Early" engine, richer Ask Liz,
comments, collections UI, FCM push, analytics dashboard) and Phase 3 hooks are
scaffolded in the models, schema, and repository interfaces.
