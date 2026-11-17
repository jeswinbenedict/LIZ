# Security audit

Audit of the repository, its full Git history, its GitHub configuration and
the live backend, carried out on 17 November 2026 as the repository was
made public. No secret values appear in this report.

How the project is secured by design (the threat model, row-level security,
each Edge Function's authentication) is in [docs/SECURITY.md](docs/SECURITY.md).
How to report a vulnerability is in [SECURITY.md](SECURITY.md).

## Summary

| Severity | Found | Fixed | Fix pending | Accepted / needs the maintainer |
| --- | --- | --- | --- | --- |
| Critical | 1 | 1 | 0 | 0 |
| High | 2 | 2 | 0 | 0 |
| Medium | 3 | 2 | 0 | 1 (M3) |
| Low | 8 | 4 | 0 | 4 |

**No credential has ever been committed**, so none needs rotating because the
repository is public. The values that look like credentials are public by
design (below).

## Findings

### Critical

**C1. Deploy workflows would deploy a fork's code with production secrets.**
`deploy-web.yml` and `deploy-supabase.yml` run on `workflow_run` after CI and
check out the commit CI ran on. Their filter `branches: [main]` matches the
*name* of the triggering branch, so a pull request from a fork's branch called
`main` would pass it. Once CI succeeded on that pull request, the attacker's
code would have been built and published to the live site with the Cloudflare
token, and their migrations and functions deployed with the Supabase access
token and database password: full control of the site and the database.

- Exposure: only since the repository became public. No fork or outside
  pull request has ever existed, and every past deploy was triggered from
  `main` of this repository, so it was never used.
- Fix: both jobs now run only when CI passed on a **push** to `main` of
  **this** repository (`workflow_run.event`, `head_repository`,
  `head_branch`). Pushed to `main` on 17 November 2026.
- Also in place: Settings → Actions → "Require approval for all
  external contributors" (was: first-time contributors only), verified through
  the API. No outside contributor's workflow runs without approval.

### High

**H1. Unencrypted database dumps stored as workflow artifacts.**
`backup-db.yml` uploaded a full `pg_dump` (the `public`, `auth` and `storage`
schemas: every account) as a workflow artifact. Artifacts of a public
repository can be downloaded by any signed-in GitHub user.

- Fixed: the eight existing dumps were downloaded, checked (valid
  PostgreSQL archives), and deleted from GitHub; none remains in any page of
  the artifact list. The workflow now encrypts each dump with AES-256 (gpg)
  from the `BACKUP_PASSPHRASE` secret, removes the plain file, and takes no
  backup at all without the passphrase.

**H2. Regular expression with exponential backtracking in Repository
Analyzer answers** (CodeQL `js/redos`, `supabase/functions/_shared/repo/ask.ts`).
The citation pattern's `(?:\/[^\]\s:]+)*` overlapped with the preceding class,
which already matched `/`. The input is an AI answer about a repository, which
an attacker can steer; a long unclosed `[a/a/a/…` could pin a function
instance.

- Fixed: the equivalent pattern without the overlapping group. A regression
  test runs 100 000 characters of hostile input in under a second.

### Medium

**M1. Error details returned to callers** (CodeQL `js/stack-trace-exposure`).
`ask-liz` (any signed-in user) and seven operator-only functions answered
failures with `String(err)` or database error messages, which can carry stack
traces, SQL, table and column names.

- Fixed: a shared `failure()` in `_shared/cors.ts` logs the full cause to the
  function's log and returns a generic message, used at all 18 places
  (three of them found by CodeQL's re-scan after the first fix).
  `summarize-tools`' structured `ai_credentials` code, which `scrape-tools.yml`
  reads, is unchanged. Tested.

**M2. Polynomial backtracking in the Product Hunt feed parser** (CodeQL
`py/redos`, `scrapers/liz_scraper/sources/producthunt.py`). Optional
whitespace on both sides of a repeated group, applied to third-party text.

- Fixed: replaced by a linear function, `strip_feed_nav`, with tests for
  behaviour and for speed on hostile input.

**M3. The maintainer's personal email address is in the public history.** All
191 of the maintainer's commits were authored with a personal address.

- Prepared, not applied: a rewritten history (in a separate clone) replaces it
  with the GitHub no-reply address. All 204 commits keep byte-identical
  content; a verified backup bundle of the original history exists.
  Force-pushing needs the maintainer's approval.
- Limitation: GitHub keeps `refs/pull/N/head` for the 25 Dependabot pull
  requests, which reach the old commits and cannot be deleted by the owner.
  Removing them, and GitHub's cached views of old commits, needs a request to
  GitHub Support after the force-push. Clones and forks made before then keep
  the old history.

### Low

| ID | Finding | Status |
| --- | --- | --- |
| L1 | `decodeXml` unescaped `&amp;` first, so `&amp;lt;` became `<` (CodeQL `js/double-escaping`). Output is shown as text, so a correctness bug. | Fixed, tested |
| L2 | `readmeIntro` could leave angle brackets from malformed tags (CodeQL `js/incomplete-multi-character-sanitization`). Output is shown as text. | Fixed, tested |
| L3 | The scraper and news bots identified themselves with `liz.app` and `hello@liz.app`, a domain the project does not own. | Fixed: they name the repository |
| L4 | Four workflows had no `permissions:` block and received the default token. | Fixed: `contents: read` unless more is needed |
| L5 | Secret scanning flags the Firebase web API key (alerts 1, 2). It is public by design and ships in every web client; access is enforced by Firebase Auth and row-level security. An older Firebase web key appears in history only. | Accepted; restricting the key and checking the old one are maintainer actions (PRODUCTION_READINESS.md) |
| L6 | The live site sends no `Cross-Origin-Opener-Policy` header. | Recommendation: needs testing with Google sign-in first |
| L7 | Edge Functions answer CORS with `*`. They authenticate with bearer tokens, never cookies, so another origin gains nothing. | Accepted |
| L8 | `ask-liz`, `logo` and `tool-updates` rate limits key on `x-forwarded-for` and fail open: a cost ceiling, not access control (docs/SECURITY.md). | Accepted, documented |

### Dismissed

Two CodeQL `py/incomplete-url-substring-sanitization` alerts in
`scrapers/tests/` are test assertions that a known host appears in a message,
not URL validation. Dismissed as "used in tests" with that comment.

## Git history

Every commit on every branch was searched for: JWTs (each decoded to read its
role), Supabase secret and service-role keys, Google, AWS, GitHub, Groq,
OpenAI, Slack and Resend key formats, private keys and certificates,
PostgreSQL connection strings with passwords, and files named like
credentials, dumps or backups.

| Found | Verdict |
| --- | --- |
| Three JWTs in launch configs and `run_web.ps1` | Supabase **anon** keys (role `anon`): public by design, shipped in the web bundle. Moved to a git-ignored `.env` anyway. |
| `AIza…` keys in the Firebase config and service worker | Firebase web API keys: public by design (L5). |
| JWT and `sb_secret_…` in `supabase/functions/tests/auth_test.ts` | Test fixtures; the JWT signature is the literal `signature`. |
| `-----BEGIN PRIVATE KEY` in `_shared/google.ts` and a test | Code that strips PEM headers, and a redaction test. No key. |
| PostgreSQL URLs | Placeholders, local defaults (`postgres:postgres@localhost`), and one pooler URL with no password. |
| Service-role key, database password, Cloudflare token, Groq key, Firebase Admin key, ingest key | **Never committed.** Each lives only in GitHub Actions or Supabase secrets. |
| SMTP, AWS, OAuth client secrets, webhook secrets, signing keys, certificates | None used by the project; none found. |
| Production data or dumps | None ever committed. |

CI now scans every push and pull request with gitleaks, and GitHub secret
scanning with push protection covers the full history and future pushes.

## Live verification

`tool/qa/probe_live.py` was run against the production backend with no
credentials and with the public anon key, sending empty bodies only:

- all 14 Edge Functions refuse (401, or 400 for an empty body before the
  sign-in check), and none is missing;
- a real question to `ask-liz` without a session is refused (401);
- all 27 tables and 6 views return no rows to the anon key, or refuse.

The live site serves CSP, HSTS, `X-Frame-Options: DENY`, `nosniff`, a
referrer policy and a permissions policy. Requests for `/.env`,
`/.git/config` and source maps return the app's own `index.html`.

## GitHub configuration

Verified through the GitHub API after each change.

| Feature | State | Note |
| --- | --- | --- |
| Visibility | Public | |
| Secret scanning | Enabled | Free for public repositories |
| Push protection | Enabled | Blocks pushes that contain recognised secrets |
| Secret scanning: non-provider patterns, validity checks | Off | Need GitHub Advanced Security (paid) |
| Private vulnerability reporting | Enabled | Linked from SECURITY.md |
| Dependabot alerts | Enabled | 0 open |
| Dependabot security updates | Enabled | |
| Dependabot version updates | Configured | `.github/dependabot.yml`: pub, pip, Actions, weekly |
| Code scanning (CodeQL default setup) | Enabled | Actions, JavaScript/TypeScript, Python. Dart is not supported by CodeQL |
| Fork pull request workflows | Approval required for all external contributors | Raised from first-time contributors only (C1) |
| Ruleset on `main` | Active: 5 required CI checks | Admin role may bypass; see PRODUCTION_READINESS.md |
| Workflow token | Read-only unless a job needs more | `deploy-supabase` writes one tag |
| `pull_request_target` | Not used | |

Forked pull requests run `ci.yml` with a read-only token and no secrets.

## Remaining concerns

1. Approve workflow runs on outside pull requests only after reading the
   change: CI runs the contributor's code (without secrets).
2. `BACKUP_PASSPHRASE` must be set, or no backups are taken.
3. The personal email in history (M3).
4. Restricting the Firebase web key and checking the old one (L5).
5. Direct pushes to `main` bypass review; requiring pull requests is
   recommended.
