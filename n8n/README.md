# Liz — Content Ingestion (n8n)

n8n pulls new/rising tools and tech news from early-signal sources, normalizes and
dedupes them, enriches with an AI summary, and writes clean rows to Supabase.
**The Flutter app never scrapes** — it only reads Liz's own clean API.

## Source priority (§10)

1. **APIs first** — Product Hunt, GitHub Trending, Hacker News (Algolia API). Stable + legal.
2. **RSS feeds** — TechCrunch, The Verge, Ars Technica, etc.
3. **Scraping last** — only where no feed/API exists (Playwright/Cheerio). Keep selectors in config.

## Workflow shape (one per source)

```
Schedule (every 30 min)
  → Fetch (HTTP Request / RSS Read)
  → Parse & Normalize → { name/title, url, category, source, image, published_at, tagline, description }
  → Compute content_hash = sha256(lower(normalized_title) + '|' + normalized_url)
  → Dedupe: skip if content_hash already exists in tools/news
  → Enrich: POST to Supabase Edge Function /summarize → ai_summary.bullets
  → Upsert into Supabase (status = 'pending' for review)
```

## Connecting to Supabase (service role — server-side only)

Use the **Supabase node** or an HTTP Request node with the service-role key. This key
bypasses RLS and must never leave the server.

Upsert example (HTTP Request → `POST {SUPABASE_URL}/rest/v1/tools`):

```
Headers:
  apikey: {SUPABASE_SERVICE_ROLE_KEY}
  Authorization: Bearer {SUPABASE_SERVICE_ROLE_KEY}
  Content-Type: application/json
  Prefer: resolution=merge-duplicates   # upsert on the unique content_hash

Body (tools):
{
  "name": "...", "slug": "...", "tagline": "...", "description": "...",
  "ai_summary": ["bullet 1","bullet 2","bullet 3"],
  "website_url": "...", "category": "ai-video", "tags": ["video","editing"],
  "platforms": ["web"], "pricing_type": "freemium", "source": "producthunt",
  "source_url": "...", "content_hash": "<sha256>", "status": "pending"
}
```

News items use the same pattern against `/rest/v1/news` (snippet + link out only — never
republish full articles).

## AI enrichment call

```
POST {FUNCTIONS_URL}/summarize
Headers: Authorization: Bearer {SUPABASE_ANON_KEY}, Content-Type: application/json
Body: { "title": "<name>", "description": "<description>", "kind": "tool" }
→ { "data": { "bullets": ["...","...","..."] } }
```

## Trend scoring

Trend/rising scores are computed in the DB. Schedule a nightly job (pg_cron or an n8n
HTTP call) to run:

```sql
select refresh_trend_scores();
```

The `tools_rising` view exposes the velocity-based "Rising Early" ranking.

## Operational rules (§10)

- Respect each source's ToS and rate limits.
- Log every run; alert on failures.
- Keep scraper selectors in a config table/file so fixes don't require redeploys.
- New items land as `status = 'pending'`; an admin approves them in the app's admin panel
  (or you can auto-publish trusted API sources).

## Ready-made workflow

`workflows/liz-ingestion.json` is importable as-is (n8n → Workflows → Import from
File). Every 6 hours it runs three branches in parallel:

1. **BeautifulSoup scraper** (Execute Command) — `scrapers/`, discovers from
   Product Hunt RSS + Hacker News and enriches from each product's own site.
2. **GitHub tools** (HTTP) — the `fetch-tools` Edge Function.
3. **Tech news** (HTTP) — the `fetch-news` Edge Function.

then refreshes the trend ranking and calls `embed-tools` so the new rows become
searchable. A tool with no embedding is invisible to Ask Liz, so that last step
is not optional.

Set these in the n8n container's environment before activating it:

```
SUPABASE_URL
SUPABASE_FUNCTIONS_URL
SUPABASE_SERVICE_ROLE_KEY
```

The Execute Command node expects the repo checked out at `/data/liz` with the
scraper's dependencies installed — adjust the path in the node if yours differs.

> Export any further workflows to `n8n/workflows/*.json` and commit them.
