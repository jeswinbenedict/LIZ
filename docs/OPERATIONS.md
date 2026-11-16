# Running Liz

What to do when something breaks, where each secret lives, and the jobs that
keep the catalog fresh. For how the pieces are built, see the other files in
this folder. Written 1 October 2026.

---

## 1. Being told when something breaks

`check_system_health()` runs hourly (pg_cron) and checks twelve signals taken
from the data itself: catalog and news freshness, embedding and summary
coverage, the unexplained backlog, failed scheduled calls, crash reports, open
reports, and whether the daily signal history is still being written. The
admin console's **Health** tab shows all of it.

When a check fails, two things happen, at most once every six hours per
failure:

- admins get an in-app notification;
- a push goes to the phone through **ntfy** (free and open source). A second
  push says when everything is healthy again.

**To receive the pushes:** install the ntfy app (Android, iOS, or
`https://ntfy.sh` in a browser) and subscribe to the topic stored in
`app_config.alert_ntfy_topic`. The topic name is the only secret — anyone who
knows it can read the alerts, which name failing checks and nothing personal.
To change it:

```sql
update app_config set value = to_jsonb('liz-<new random string>'::text)
 where key = 'alert_ntfy_topic';
```

`alert_ntfy_server` points at `https://ntfy.sh`; set it to your own ntfy
server to self-host. `select push_alert('Test', 'Hello', 3, '{}');` sends a
test.

## 2. Reading a crash report

Crash reports land in `error_events` and the Health tab. The release build is
minified, so a stack reads `main.dart.js:2:51234`. Every deploy keeps its
source maps as a GitHub Actions artifact named `sourcemaps-<version>`, where
the version is the seven-character commit the report's `app_version` carries.

1. Actions → the deploy-web run for that commit → download
   `sourcemaps-<version>`.
2. Paste the stack into a file and run:

```bash
python tool/symbolicate.py main.dart.js.map < stack.txt
```

Each frame gains the Dart file and line it came from. The maps are kept for
90 days.

## 3. Backups and restoring

`backup-db.yml` takes a `pg_dump` of the `public`, `auth` and `storage`
schemas every Sunday at 02:00 UTC and keeps it as an artifact for 90 days
(about thirteen restore points). It does nothing until the secret
`SUPABASE_DB_URL` is set (the Session pooler URI from the Supabase dashboard,
with the database password filled in).

To restore into an empty database:

```bash
pg_restore --no-owner --no-privileges -d "<connection string>" liz.dump
```

Then run `supabase db push` against it so the migration history matches, and
redeploy the functions (section 4). Logo files in Storage are not in the dump:
`python -m liz_scraper.store_logos --apply` copies them again from the source
sites.

Run a restore into a scratch project once, before it matters.

## 4. Deploying

Nothing deploys from a laptop by default. Both deploy workflows run only after
CI passes on `main`:

| Workflow | Deploys | Needs |
|---|---|---|
| `deploy-supabase.yml` | migrations and Edge Functions, only when `supabase/` changed | `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD` |
| `deploy-web.yml` | the web build, prerendered pages and badges to Cloudflare Pages; also daily at 05:30 UTC so pages stay fresh | `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `SITE_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `FCM_VAPID_KEY` |

By hand, from the repository root:

```bash
supabase db push
supabase functions deploy <name>
```

`supabase/config.toml` decides which functions check the caller's JWT; keep it
in step with each function's own auth.

`main` is protected by the ruleset "main: CI must pass before merging"
(Settings → Rules): a pull request merges only when CI's `flutter`, `scrapers`,
`edge-functions`, `migrations` and `browser` jobs have passed (a job skipped
because its files did not change counts as passed). That includes
Dependabot's: on 13 November 2026 a Firebase update whose CI had failed (two
deprecations, which `flutter analyze` treats as errors) was merged, and `main`
stayed red until it was fixed. Repository admins can still push directly and
can override the rule on a pull request, but only by ticking "bypass rules".

The web deploy ends with a smoke test (home page, a tool page's title, the
sitemap, robots.txt). A failed smoke test fails the run but does not roll
back: redeploy the previous commit from the Actions tab.

## 5. Scheduled work

| Where | Job | When |
|---|---|---|
| pg_cron | `fetch-news-hourly` | hourly |
| pg_cron | `fetch-tools-daily` (GitHub) | daily |
| pg_cron | `snapshot-and-rank-daily` | daily, 04:50 UTC |
| pg_cron | `backfill-embeddings`, `backfill-summaries` | every 15 minutes |
| pg_cron | `backfill-news-summaries` (news quick takes, last 48 hours) | every 15 minutes |
| pg_cron | `check-system-health-hourly` | hourly |
| pg_cron | `prune-*`, `cap-news-rows` | daily housekeeping |
| GitHub Actions | `scrape-tools.yml`: Hacker News scrape, logos, malware check | daily, 03:30 UTC |
| GitHub Actions | `backup-db.yml` | Sundays |
| n8n (this laptop) | Product Hunt scrape | see `n8n/README.md` |

`fetch-news.yml` has no schedule: pg_cron already runs it, and the workflow is
kept for a manual run.

## 6. Keeping the catalog clean

All from `scrapers/`, with the service key in the environment. Each prints
what it would do; add `--apply` to do it.

| Command | Does |
|---|---|
| `python -m liz_scraper.dedupe_tools` | hides duplicate listings of one site, keeping the oldest and its signals |
| `python -m liz_scraper.store_logos` | copies logos into the `logos` Storage bucket as 128px WebP |
| `python -m liz_scraper.threats` | holds back any tool whose site is on the malware list (URLhaus) or the phishing list (OpenPhish, PhishTank, PhishStats); exits 1 if neither list could be fetched |
| `python -m liz_scraper.backfill_pricing` | fills in missing prices from tool sites |

New listings are checked for duplicates (`site_key`), malware and phishing on the way in;
these commands are for the catalog that already exists.

**News linking** (migrations 0052–0053) joins a headline to a tool when it
names the tool. A name that is an everyday word ("Switch", "Ember") is on the
stop list in `ambiguous_tool_name()`; add to it if a tool page shows headlines
that are not about it, then rerun the back-fill at the end of 0053.

## 7. Accounts

Sign-in is Firebase Authentication; profiles and everything else are here.
Setup, the claims, and how the pre-switch account is linked:
[AUTH.md](AUTH.md). To find who a Firebase account is:

```sql
select p.* from firebase_accounts fa join profiles p on p.id = fa.user_id
 where fa.email = 'someone@example.com';
```

To make someone an admin, set `profiles.role`; their next request sees it.

## 8. Secrets

| Secret | Lives in | Used by |
|---|---|---|
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | GitHub Actions; public by design | web build, prerender |
| `SUPABASE_SERVICE_ROLE_KEY` | GitHub Actions | scrapers, `fetch-news.yml` |
| `INGEST_KEY` / `LIZ_INGEST_KEY` | Supabase function secret; `~/.liz/n8n.env` | the laptop scraper, through `scraper-ingest` only |
| `SUPABASE_FUNCTIONS_URL` | GitHub Actions | `fetch-news.yml` |
| `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD` | GitHub Actions | `deploy-supabase.yml`. The access token expires: renew it (Supabase → Account → Access Tokens) before about 3 January 2027, or backend deploys fail |
| `SUPABASE_DB_URL` | GitHub Actions | `backup-db.yml` |
| `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `SITE_URL` | GitHub Actions | `deploy-web.yml` |
| `FCM_VAPID_KEY` | GitHub Actions | web build (browser notifications) |
| `AI_API_KEY`, `AI_BASE_URL`, `AI_MODEL` | Supabase function secrets | summaries (Groq by default). The key can expire: when the provider refuses it, `scrape-tools` shows an "AI key refused" warning and a note in the run summary (the scrape itself still succeeds; summaries resume on their own once the key works); create a new key and `supabase secrets set AI_API_KEY=…` |
| `AI_FALLBACK_API_KEY`, `AI_FALLBACK_BASE_URL`, `AI_FALLBACK_MODEL` | Supabase function secrets, optional but recommended | used when the first provider fails, including a refused key; a second provider (OpenRouter or Gemini, both free) keeps summaries running through the next expiry |
| (none new) | | The Repository Analyzer (`analyze-repo`, `ask-repo`) uses the existing `SUPABASE_*`, `FIREBASE_SERVICE_ACCOUNT` and `AI_*` secrets. GitHub needs no key: public repositories are read anonymously, private ones with a token the person pastes for that run (never stored). See docs/REPO_ANALYZER.md |
| `FIREBASE_SERVICE_ACCOUNT` | Supabase function secrets | `send-notification`, `firebase-session`, `delete-account` (Admin SDK key of `liz-f5f93`) |
| `ASK_EVAL_KEY` | Supabase function secrets | lets the Ask Liz evaluation skip the rate limit |
| ntfy topic | `app_config.alert_ntfy_topic` | health pushes |

Set function secrets with `supabase secrets set NAME=value`. The laptop holds
no Supabase key: rotating the service key means GitHub Actions only, and
rotating the ingest key means the function secret and `~/.liz/n8n.env`
together.
