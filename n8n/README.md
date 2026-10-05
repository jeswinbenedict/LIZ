# Running the scraper from your own machine (n8n)

Most of Liz's scheduled work runs inside Supabase and needs nothing from you:
pg_cron fetches GitHub tools daily and news hourly, backfills embeddings and
summaries every fifteen minutes, refreshes the rankings, and runs the health
checks. A GitHub Actions workflow scrapes Hacker News daily as well; it no
longer tries Product Hunt, which this workflow now owns.

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

Every twelve hours — or whenever you press **Run now** in the editor, which is
also what the CLI's `execute` starts from — in order:

1. **Scrape new launches** — `python -m liz_scraper --limit 30`. Product Hunt and
   Hacker News. The quality gate in `liz_scraper/quality.py` decides whether each
   row is published or held; there is deliberately no `--status` flag here, which
   would bypass it.
2. **Retry held listings** — `python -m liz_scraper.retry_held --apply --limit 50`.
   Product Hunt rows written while the scraper ran somewhere blocked are held
   because their website is still the listing. This re-reads each one from here.
   Fifty per run keeps it polite; the backlog drains over a few runs.
3. **Summarise run** — pulls the JSON report out of both commands' output and
   gives a verdict: `ok`, a command that did not finish (with its error), or
   every held listing still unreachable, meaning this machine is blocked too.
4. **Verdict ok?** — anything but `ok` ends at **Mark the run failed**, so a bad
   run shows red in the execution list instead of passing as green.

A failed scrape does not stop the retry, and neither stops the summary: the
summary is where a failure gets explained.

It does not fetch news, GitHub tools, embeddings or summaries — pg_cron already
does all of those, and running them here as well would double every job.

## Setting it up

This runs on **self-hosted n8n on the machine at home** — the free community
edition, not n8n Cloud. n8n Cloud cannot do this job: it runs from datacenter
addresses that Product Hunt blocks, it does not offer the Execute Command node
the workflow is built on, and it is a paid plan after its trial.

Everything lives in `~/.liz`, outside this repository (which OneDrive syncs):

| Path | What | How it was made |
|---|---|---|
| `~/.liz/node24/` | Portable Node 24 LTS, used by n8n only | the `win-x64.zip` from nodejs.org/dist/latest-v24.x, checksum-verified |
| `~/.liz/n8n/` | n8n 2.40.7 | `npm install n8n@2.40.7`, run with that Node 24 |
| `~/.liz/scraper-venv/` | Python 3.11 with the scraper's requirements | `python -m venv`, then `pip install -r scrapers/requirements.txt` |
| `~/.liz/n8n.env` | `SUPABASE_URL` and `LIZ_INGEST_KEY` | readable by your account only |

Why each is separate:

- **Node 24, not the system's.** n8n needs Node 24 or later, but one of its
  dependencies (`isolated-vm`) has no prebuilt binary for Node 25 and would
  need a C++ toolchain. The LTS line installs cleanly; the system Node is left
  alone.
- **Its own Python.** A bare `python` on this machine resolves to another
  tool's virtual environment. The workflow names this one explicitly.
- **A key that opens one door.** `LIZ_INGEST_KEY` works only on the
  `scraper-ingest` function, which does exactly what these two commands need:
  look up published tools, write new or re-scraped listings (never rewrite a
  published one, never hide anything), and re-try held ones. Until 6 October
  2026 this file held the service role key, which reads and writes the whole
  database — profiles, notifications, storage — so a lost laptop was a lost
  database. The key still lives in a file only you can read, never in the
  repository or in n8n's own database. It matches the `INGEST_KEY` function
  secret; to rotate, set a new one in both places
  (`supabase secrets set INGEST_KEY=…`).

### Starting it

```powershell
powershell -ExecutionPolicy Bypass -File n8n\start-n8n.ps1
```

Then open <http://localhost:5678>. The script:

- loads `~/.liz/n8n.env` into the process, so the scraper inherits the keys;
- sets `LIZ_REPO_DIR` and `LIZ_PYTHON`, which the commands read through the
  shell (`%LIZ_PYTHON%`). Not through n8n's `$env`, which n8n 2.x blocks in
  expressions — and should: allowing it would hand the key to every
  expression and Code node;
- re-enables Execute Command (`NODES_EXCLUDE=[]`), which n8n 2.x turns off;
- binds n8n to `127.0.0.1` only, because a node that can run commands must not
  be reachable from the network;
- forces UTF-8 for Python, since Windows pipes default to cp1252 and the first
  non-ASCII tool name would end the run;
- turns off n8n's telemetry.

Anything after the script name is passed to the n8n CLI:

```powershell
n8n\start-n8n.ps1 import:workflow --input=n8n\workflows\liz-scrape-from-home.json
n8n\start-n8n.ps1 execute --id=LizScrapeHome001
```

The workflow has a fixed id, `LizScrapeHome001`, so importing it again updates
it rather than creating a copy. The commands use `cmd.exe` syntax; on Linux or
Docker they would read `cd "$LIZ_REPO_DIR/scrapers" && "$LIZ_PYTHON" …`.

### The first visit

The first time <http://localhost:5678> opens, n8n asks you to create its owner
account. That account exists only in this local n8n.

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
