# Liz — tool scraper (open source)

Discovers new AI tools from free sources, enriches each one by reading its own
website with BeautifulSoup, and upserts clean rows into the Supabase `tools`
table. No paid APIs anywhere in this path.

## How it works

```
discover            dedupe                  enrich                 write
─────────           ──────                  ──────                 ─────
Product Hunt RSS ┐  skip content_hashes  →  fetch the product's →  upsert into
Hacker News API  ┘  already in Supabase     own page (bs4):        tools, on
                                            title, description,    conflict
                                            logo, pricing,         content_hash
                                            platforms, category
```

Dedupe happens **before** enrichment, so a re-run costs almost no requests.

New rows land as `status = 'pending'` — they do not appear in Discover until an
admin approves them in the app's admin panel.

## Running it

```bash
pip install -r requirements.txt

# See what it would write, without touching the database
python -m liz_scraper --dry-run --limit 10

# One source only
python -m liz_scraper --dry-run --source hackernews

# Write for real (needs credentials, see below)
python -m liz_scraper --limit 20 --status pending
```

Credentials come from the environment and are never committed:

```bash
export SUPABASE_URL="https://<ref>.supabase.co"
export SUPABASE_SERVICE_ROLE_KEY="<service role key>"
```

The service-role key bypasses RLS. Keep it on servers only — it must never be
bundled into the Flutter app.

## Being a good citizen

`http_client.py` enforces this on every outbound request:

- reads `robots.txt` for our own user agent and **skips** anything disallowed
- honours the host's `Crawl-delay`, defaulting to 1.5s between hits per host
- retries only on 429/5xx, with exponential backoff
- identifies itself honestly via a descriptive User-Agent

Discovery uses sanctioned feeds and public APIs (Product Hunt RSS, the Hacker
News Algolia API). BeautifulSoup is pointed at each product's *own* homepage —
first-party public metadata — rather than at a competitor directory's listings.
Store-listing hosts (App Store, Google Play) are skipped because they return
the platform's boilerplate copy instead of the product's own description.

## Tests

```bash
python -m pytest tests -q
```

The parsing and normalization logic is covered offline with fixture HTML, so the
suite runs in CI without network access.

## Scheduling

Two options, both already wired:

- **GitHub Actions** — `.github/workflows/scrape-tools.yml`, daily. Free, no
  infrastructure. Add `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` as repo
  secrets.
- **n8n** — `n8n/workflows/liz-ingestion.json`, every 6 hours, alongside the
  Edge Function ingestion and the trend-score refresh.

## Adding a source

1. Write `sources/<name>.py` exposing
   `discover(session, *, limit) -> list[Candidate]`.
2. Register it in `sources/__init__.py` under `ALL_SOURCES`.

It automatically inherits dedupe, enrichment, rate limiting, and the CLI flag.
