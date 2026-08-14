# Liz — Data Architecture

## Principle
**Supabase is the single live backend.** It provides the things a deployed app
needs and that plain PostgreSQL does not: **Auth (JWT), Row-Level Security,
Realtime, Storage, and Edge Functions**. A PostgreSQL server on a local PC is not
internet-reachable and has none of those layers, so it can **never** be the
production database for the app. Instead we keep Supabase small and give local
PostgreSQL a supporting role.

```
Deployed app (web + mobile)
      │  auth · RLS · realtime · storage · functions
      ▼
  SUPABASE (live)  ── Postgres (lean) · Auth · Storage · Realtime · Edge Fns
      │  (optional, offline)              ▲ (GUI manage)
      ▼                                   │
  Local PostgreSQL  ◄──── pgAdmin ────────┘
  = management + archive + dev   (NOT the live backend)
```

## Keeping Supabase lean (automated)
The only high-churn table is `news` (the hourly `fetch-news` job adds
~80–100 rows/hour). Retention is automated in `supabase/migrations/0006_retention.sql`:

| Job (pg_cron) | Schedule | Effect |
|---|---|---|
| `fetch-news-hourly` | `0 * * * *` | Ingest latest tech news |
| `prune-old-news` | `30 3 * * *` | Delete `news` older than 30 days |
| `prune-read-notifications` | `35 3 * * *` | Delete read notifications older than 30 days |

Net effect: the DB stays a few MB indefinitely (currently ~12 MB of ~500 MB free).

Check jobs anytime:
```sql
select jobname, schedule, active from cron.job order by jobname;
```

## Images (Storage)
Uploads are compressed client-side (resized, quality 82) and stored in the
`avatars` / `post-images` buckets. 1 GB holds thousands of them. If it ever
fills, offload to free object storage (e.g. Cloudflare R2 — 10 GB free) by
swapping the bucket target in `lib/core/storage/storage_service.dart`; no schema
change needed.

## Local PostgreSQL — its proper roles

### 1) Manage the live data with pgAdmin
Connect pgAdmin directly to the **Supabase** database (browse/query the real data):

1. Supabase Dashboard → **Project Settings → Database → Connection info**
   (use the **Session pooler** / port `5432`, or the pooler on `6543`).
2. In pgAdmin: **Object Explorer → right-click Servers → Register → Server…**
   - **General → Name:** `Liz (Supabase)`
   - **Connection → Host:** `<from dashboard>` (e.g. `aws-0-...pooler.supabase.com`)
   - **Port:** `5432` (or `6543`)
   - **Maintenance database:** `postgres`
   - **Username:** `postgres.<project-ref>` (shown in the dashboard)
   - **Password:** your database password (set at project creation)
   - **Save password:** yes
3. Save → expand → `Databases → postgres → Schemas → public → Tables`.

> Tip: enable SSL (Connection → Parameters → `sslmode = require`).

### 2) Archive old news before it's pruned (optional)
If you want to keep news beyond the 30-day window for history/analytics, copy it
to local PostgreSQL before the nightly prune. Using `psql` (bundled with your
PostgreSQL install):

```sql
-- one-time: on your LOCAL Postgres, create an archive table
create table if not exists news_archive (like public.news including all);
```

```bash
# export recent news from Supabase to CSV (run in a terminal; <...> = your values)
psql "postgresql://postgres.<ref>:<db-password>@<host>:5432/postgres?sslmode=require" ^
  -c "\copy (select * from public.news) to 'news_export.csv' csv header"

# import into local Postgres
psql "postgresql://postgres:<local-password>@localhost:5432/liz_archive" ^
  -c "\copy news_archive from 'news_export.csv' csv header"
```

Schedule it (Windows Task Scheduler, daily) if you want a growing local archive.

### 3) Local development sandbox
Experiment against a local copy without touching Supabase quota. For a **full**
local backend (Postgres + Auth + Storage + Realtime) use the Supabase CLI's Docker
stack — this is the supported local-dev path, not a bare PC Postgres:
```bash
supabase start      # requires Docker Desktop running
```

## If you outgrow the Supabase free tier
A PC Postgres still can't serve the app. Real options, in order:
1. **Supabase Pro** — $25/mo, 8 GB DB, 100 GB storage. Zero migration.
2. **Self-host the full Supabase stack** on a small VPS (it's open source) —
   Postgres + GoTrue + Realtime + Storage + Kong. More ops work; still a public server.
3. **Managed Postgres** (Neon / Railway) — but you'd re-add auth/realtime/storage.

With 30-day retention in place, the free tier comfortably covers an MVP and well
beyond.
