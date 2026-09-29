# How Liz ranks tools

Liz's promise is finding AI tools *while they are still rising*. Until
September 2026 nothing measured rising: the chart ranked tools by view counts
and ratings typed into a seed file (ChatGPT "982,000 views", Claude "4.8 from
18,400 ratings") while the app recorded no views at all and the reviews table
was empty. Migration 0037 removed those figures and replaced the ranking.

## What is measured

| Signal | Where it comes from | How often |
|---|---|---|
| GitHub stars | GitHub search API, many `repo:` terms per query | daily, `python -m liz_scraper.signals` |
| Hacker News points and comments | Algolia HN API, by story id | daily, for stories under 30 days old |
| Views of a tool's page | `track('tool_view')` from the app | as they happen, once per visitor per 30 min |
| Visits to a tool's website | `track('outbound_click')` | as they happen, once per visitor per 30 min |
| Saves | `track('save')`, signed in or not | once per visitor per tool |

Events go into `events` through `track()` only. It drops unknown names,
oversized payloads, repeat views, and floods from one address. The only
identifier is a random id the browser keeps; no IP address is stored.

## History

`tool_signal_snapshots` has one row per published tool per day, holding the
outside figures and the running totals from the event log. It is written by
`snapshot_signals()`, nightly by pg_cron (`snapshot-and-rank-daily`, 04:50
UTC) and again by the scraper workflow after it reads outside signals.

**A missed day cannot be recovered.** The health check
`signal_history_hours` fails if the newest snapshot is more than two days old.

## Momentum

`refresh_trend_scores()` compares the newest snapshot with the oldest one in
the last seven days and adds three terms:

- **GitHub** — `ln(1 + new stars) + ln(1 + 100 × new stars / (stars a week ago + 1000))`.
  The second part is relative: 500 new stars mean more to a 1k-star repo than
  to a 100k-star one.
- **Hacker News** — `ln(1 + new points)`. For a tool Liz first saw this week,
  all its points count, since they were earned this week.
- **Liz** — `1.2 × ln(1 + 3 × saves + website visits + 0.3 × views)`, all new
  this week.

The largest term becomes `trend_reason`, in words ("+1.2k GitHub stars this
week", "227 points on Hacker News", "+3 saves on Liz this week"), which is what
the app shows. `trend_score` is the percentile of momentum across the catalog
(0 for tools with none) and `trend_rank` the position.

A tool with no measured growth has momentum 0 and no reason, and does not
appear in "Rising this week". That includes famous tools: being well known is
not rising.

## Running it by hand

```bash
cd scrapers
python -m liz_scraper.signals --dry-run   # read, print, write nothing
python -m liz_scraper.signals             # read, write, snapshot, rank
```
