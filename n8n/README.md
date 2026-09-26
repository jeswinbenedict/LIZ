# Running the scraper from your own machine (n8n)

Most of Liz's scheduled work runs inside Supabase and needs nothing from you:
pg_cron fetches GitHub tools daily and news hourly, backfills embeddings and
summaries every fifteen minutes, refreshes the rankings, and runs the health
checks. A GitHub Actions workflow runs the scraper daily as well.

This workflow exists for one thing those cannot do: **reach Product Hunt.**

## Why it has to run here

Product Hunt's edge returns `403` to datacenter IP addresses — every GitHub
Actions runner, every cloud function. Their `robots.txt` allows `/products/*`,
so the scraper is not doing anything they have asked it not to; it is simply
being turned away by address. From a home connection the same code works.

Measured on 26 September 2026, same code, same day:

| Where it ran | Product Hunt launches that reached their product page |
|---|---|
| GitHub Actions runner | 0 of every run, `403` on each listing |
| This machine | 6 of 6 |

The scraper does not work around the block — no rotating user agents, no
proxies. Running it from a connection that is not blocked is the honest fix.

## What it does

Every twelve hours, in order:

1. **Scrape new launches** — `python -m liz_scraper --limit 30`. Product Hunt and
   Hacker News. The quality gate in `liz_scraper/quality.py` decides whether each
   row is published or held; there is deliberately no `--status` flag here, which
   would bypass it.
2. **Retry held listings** — `python -m liz_scraper.retry_held --apply --limit 50`.
   Product Hunt rows written while the scraper ran somewhere blocked are held
   because their website is still the listing. This re-reads each one from here.
   Fifty per run keeps it polite; the backlog drains over a few runs.
3. **Summarise run** — pulls the JSON report out of both commands' output, and
   if every held listing was still unreachable, says that this machine is blocked
   too rather than letting the run look like it succeeded.

It does not fetch news, GitHub tools, embeddings or summaries — pg_cron already
does all of those, and running them here as well would double every job.

## Setting it up

1. **Get the code and its dependencies.** Clone the repository somewhere
   permanent and install the scraper's requirements:

   ```bash
   pip install -r scrapers/requirements.txt
   ```

2. **Give n8n three environment variables** — however you run it (Docker
   `-e` flags, a `.env` file, or system variables for `npx n8n`):

   | Variable | Value |
   |---|---|
   | `LIZ_REPO_DIR` | The repository's full path, with forward slashes — e.g. `C:/Users/you/LIZ` or `/data/liz` in Docker |
   | `SUPABASE_URL` | `https://<project-ref>.supabase.co` |
   | `SUPABASE_SERVICE_ROLE_KEY` | The service-role key. It bypasses row-level security, so it stays on this machine and never goes anywhere else. |

   The workflow reads `LIZ_REPO_DIR` through an n8n expression. If your n8n
   blocks environment access in expressions, set
   `N8N_BLOCK_ENV_ACCESS_IN_NODE=false`.

3. **Import** `workflows/liz-scrape-from-home.json` (Workflows → Import from
   File), run it once by hand, and check the last node says `"verdict": "ok"`.
   Then activate it.

## Checking it worked

The **Summarise run** node's output is the place to look:

```json
{
  "scrape": { "discovered": 30, "published": 11, "held": { ... } },
  "retry":  { "held_listings_tried": 50, "published": 47, "unreachable": 0 },
  "blocked": false,
  "verdict": "ok"
}
```

In the app, the admin console's **Content** tab filtered to *Pending* shows
what is left and why each row is held.

## Running it without n8n

The two commands work on their own, from the `scrapers/` directory, with the
same two Supabase variables set:

```bash
python -m liz_scraper --limit 30
python -m liz_scraper.retry_held --apply --limit 50
```

`retry_held` without `--apply` reports what it would change and writes nothing.
