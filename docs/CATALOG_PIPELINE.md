# How a tool gets into the catalog

Liz finds tools automatically and shows them automatically. This is the rule
that decides which of those two happens, and what to do when a tool is stuck
between them.

## The path

```
source feed  →  enrich  →  quality gate  →  published
   (Atom)      (follow to     (quality.py)      or
                the product)                 pending + hold_reason
```

1. **Discover.** `sources/producthunt.py` and `sources/hackernews.py` read a
   feed and return candidates: a name, a tagline, and the URL where the tool was
   *found*.
2. **Enrich.** `enrich.resolve_and_enrich` follows a listing URL through to the
   product's own page, and reads the description, logo, category and pricing
   from there. A directory entry is where a tool was found, not where it lives.
3. **Gate.** `quality.assess` decides whether the finished row is fit to show.
4. **Write.** Rows that pass are written `published`. Rows that do not are
   written `pending` with `hold_reason` set to the first thing wrong.

## What the gate asks

It is deliberately about usefulness to a reader, not completeness.

**Refused:**

- No name, or a name that reads as a headline rather than a product — over six
  words or sixty characters. Hacker News gives the submission title, and for a
  lab announcement that is a sentence.
- No website, or a website that is still the aggregator listing. This is the
  most important rule: a catalog of links back to another catalog is not a
  catalog.
- A website that is someone's write-up rather than the product — Medium,
  Reddit, X, YouTube.
- No tagline, or one too short to say anything.
- No description.

**Not refused.** A missing logo, unknown pricing, and empty tags all pass. A
card without a logo still tells someone what the tool does, and the initial
tile is designed for exactly that. Holding a tool back over pricing we have not
worked out yet helps nobody.

The gate lives in one place, `scrapers/liz_scraper/quality.py`, and runs both at
ingest and over rows already stored, so there is no second definition to drift
from the first.

## Working the backlog

```bash
python -m liz_scraper.review            # report, change nothing
python -m liz_scraper.review --apply    # publish what passes, record the rest
```

Needs `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`. It is idempotent: running
it twice publishes nothing the second time.

The admin console's **Content** tab is the human half — filter by status, search,
page through, tick several rows and publish or hide them together. It opens on
`pending` because that is the queue that needs a person.

## Product Hunt is currently blocked

Every Product Hunt row in the backlog is held with:

> website is still the producthunt.com listing, not the product

Their `robots.txt` **allows** `/products/*`, so this is not a policy we are
ignoring — their edge returns `403` to datacenter IPs, so the enrichment step
cannot reach the product page from a GitHub Actions runner and falls back to the
listing URL.

We do not work around it. Rotating user agents or proxying to look like a
browser would be evading a block the site clearly intends, and the scraper is
built the other way round: it reads `robots.txt`, honours crawl delay, and skips
sources that disallow it.

Two honest ways forward:

- **Run the scrape from a different host.** The `n8n/` workflow is designed for
  this, and a residential IP is not usually blocked. This is the existing plan.
- **Use Product Hunt's official API,** which returns the product's real website
  and needs a developer token.

Until one of those happens, those rows stay pending with their reason recorded.
They are not deleted, and they are not counted as an unreviewed backlog.

## Why pending rows are retried

`SupabaseSink.existing_hashes` treats only **published** rows as settled. The
content hash is taken from the listing URL, so a row held back because
enrichment could not reach the product page would otherwise be skipped on every
future run and never get a second chance. Candidates come from a feed capped per
run, so retrying costs one pass over whatever is currently on the front page.

## Watching it

`system_health()` reports `unexplained_backlog`: pending tools with **no**
recorded reason. Rows held for a reason are working as designed. Rows sitting
pending with nothing to explain them mean something wrote around the gate, and
those are the ones worth a person's time. It warns above 20 and fails above 100.
