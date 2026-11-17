# Changelog

Notable changes to Liz. Liz is deployed continuously from `main` and has no
versioned releases, so changes are grouped by month. The commit history has
the detail.

## Unreleased

- Prepared for public release under the Apache License 2.0: LICENSE, NOTICE,
  third-party licence list, contribution, conduct, security and support
  policies, issue and pull request templates.
- Database backups are encrypted before they are stored as workflow
  artifacts.
- CI scans every change for committed secrets (gitleaks) and checks
  dependencies for known vulnerabilities (OSV-Scanner). Workflows run with a
  read-only token unless they need more.
- Local runs read Supabase settings from a git-ignored `.env`
  (`.env.example`) instead of values written into launch configurations.

## 2026-11

- Repository Analyzer: paste a GitHub repository (HTTPS, SSH or
  `gh repo clone`) and get its stack, architecture, data, API, build,
  deployment, security and quality, and answers cited to path and line.
- Sign-in page with seven illustrated characters whose eyes follow the
  pointer.
- Ambient red light behind every page, drawn by a GPU shader that moves and
  responds to the pointer, with a still version for reduced motion and
  browsers without WebGL.
- A refused AI provider key pauses summaries with a warning instead of
  failing the scrape.

## 2026-10

- Firebase Authentication in front of Supabase. Google sign-in served from
  Liz's own address, and every page behind sign-in.
- "Signal" redesign in black and red, then refined across every screen, with
  "the Rise" mark.
- News linking, preferences, logos stored in Supabase Storage, alerts and a
  fallback AI provider.
- Scrapers: deduplication, malware and phishing screening, badges,
  alternatives pages.
- Security: fixes from Supabase's security advisor, a privilege escalation to
  admin closed, an enforced content security policy, and a key for the home
  scraper that opens one function instead of the database.
- Link previews for shared pages.

## 2026-09

- BeautifulSoup scraper with a quality gate, scheduled from GitHub Actions
  and self-hosted n8n.
- Ask Liz: semantic search on open-source `gte-small` embeddings and
  pgvector.
- Honest ranking from recorded signals, pages for search engines, signal
  lines, tool timelines, alerts, price filters, password reset, privacy
  policy and terms, crash telemetry and health checks.
- Security: an open relay in the image proxy, unauthenticated ingestion
  functions and an open AI endpoint were closed.

## 2026-08

- First version: AI tool catalog with GitHub ingestion, a real-time news
  feed, tool detail pages, live ranking, and push and in-app notifications.
