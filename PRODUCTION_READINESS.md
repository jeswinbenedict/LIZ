# Production readiness

State of the Liz deployment and repository, assessed on 17 November 2026
after the repository was made public. Findings and fixes are in
[SECURITY_AUDIT.md](SECURITY_AUDIT.md); what was run, and with what result,
is in [TEST_REPORT.md](TEST_REPORT.md).

## Assessment

**Ready for production use and public contributions.** The one critical
finding (SECURITY_AUDIT.md, C1: deploy workflows that would have deployed a
fork's code) is fixed, and workflows on pull requests from outside
contributors also need the maintainer's approval to run.

The application builds, every automated suite passes, the live backend
refuses every unauthenticated request it should, and no table or view returns
rows to the public key. The items under "Outstanding manual actions" need the
maintainer's accounts and cannot be done from the repository.

## Deployment

| Part | Where | Deployed by |
| --- | --- | --- |
| Web app (Flutter, CanvasKit) | Cloudflare Pages, <https://liz-cfp.pages.dev> | `deploy-web.yml`, after CI passes on a push to `main`, and daily at 05:30 UTC |
| Sign-in relay | Cloudflare Pages Function, `functions/__/[[path]].js` | with the web app |
| Database, RLS, cron jobs | Supabase project `yluabeijvbydxczfxclk` | `deploy-supabase.yml`, when `supabase/` changed |
| Edge Functions (14) | Supabase | `deploy-supabase.yml` |
| Identity | Firebase project `liz-f5f93` | Firebase console (not from the repository) |
| Scraper | GitHub Actions daily; n8n on a home machine every 12 hours | `scrape-tools.yml`, `n8n/` |
| Backups | Encrypted workflow artifacts, weekly, 90 days | `backup-db.yml` |

Production uses only production endpoints: the build reads `SUPABASE_URL`,
`SUPABASE_ANON_KEY` and `FCM_VAPID_KEY` from GitHub Actions secrets, and
without them the app runs on bundled demo data rather than any development
backend. No development credentials, test accounts or debug endpoints are
deployed; requests for `/.env`, `/.git/config` and source maps on the live
site return the app's own `index.html`.

## Environment requirements

- **Build:** Flutter 3.47.2 (stable), Dart 3.12.
- **Edge Functions:** Supabase's Deno runtime; Deno 2.x for local tests.
- **Scraper:** Python 3.12 with `scrapers/requirements.txt`.
- **Configuration:** `.env.example` (web build, public values only),
  `supabase/functions/.env.example` and `scrapers/.env.example` (server
  secrets). Every production secret, where it is set and what uses it:
  [docs/OPERATIONS.md](docs/OPERATIONS.md#8-secrets).

## Outstanding manual actions

In order of importance. Each needs a dashboard or an approval only the
maintainer has.

1. **Set the `BACKUP_PASSPHRASE` secret** (GitHub → Settings → Secrets and
   variables → Actions), and keep the passphrase in a password manager.
   Until it is set, weekly backups are skipped with a warning.
2. **Restrict the Firebase web API key** in Google Cloud console → APIs &
   Services → Credentials: HTTP referrers `https://liz-cfp.pages.dev/*` and
   `http://localhost:*/*`, and only the APIs Firebase Auth and Cloud Messaging
   use. Then close secret-scanning alerts 1 and 2 as "Won't fix", with the
   comment that it is a restricted, public Firebase web key. The key is public by design, but a restriction stops it being
   used from other sites against the project's quotas.
3. **Check the older Firebase web key** that appears only in history (prefix
   `AIzaSyA9X8p7`): if it still exists in any Google Cloud project, delete it.
4. **Decide on the email rewrite** (SECURITY_AUDIT.md, M3): a rewritten
   history is ready but needs approval to force-push, and GitHub Support to
   purge pull-request references.
5. **Keep the downloaded backups private.** The eight dumps removed from
   GitHub are in `C:\Users\jeswi\liz-db-backups`, outside the repository.
   They hold every account: move them to encrypted storage or delete them
   when no longer needed.
6. **Renew `SUPABASE_ACCESS_TOKEN`** before about 3 January 2027, or backend
   deploys fail.
7. **Legal read** of the privacy policy and terms, which were written from the
   code.

## Recommendations

- **Cross-Origin-Opener-Policy.** The site sends every other recommended
  security header. Add `Cross-Origin-Opener-Policy: same-origin-allow-popups`
  to `web/_headers` only after testing Google sign-in with it, since a
  stricter value breaks the sign-in popup.
- **Require pull requests for `main`.** The ruleset requires five CI checks,
  but the repository admin role may bypass it, and every change so far has
  been pushed directly. Requiring a pull request (with the admin bypass kept
  for emergencies) gives CodeQL and the secret scan a chance to block a change
  before it deploys.
- **Custom domain.** Some networks block `*.pages.dev`. Add the domain to
  Firebase's authorized domains and to `SITE_URL` at the same time.
- **Dependency updates** arrive weekly from Dependabot, one per pull request,
  and are merged only when CI passes. At the time of writing five direct
  packages have compatible minor updates and none has a known vulnerability.
- **Restore drill.** Restore one encrypted backup into a scratch Supabase
  project once (docs/OPERATIONS.md §3), so the passphrase and procedure are
  known to work before they are needed.
