# Security notes

What is protected, how, and what was found when it was actually probed against
the live project on 26 September 2026.

## The anon key is public

It ships inside the client bundle. Anyone who opens Liz has it. Everything below
follows from that: "requires a valid JWT" and "public" are the same sentence
unless something also checks *which* JWT.

## Row Level Security

RLS is enabled on all 14 tables. Probed as an anonymous caller:

| Attempt | Result |
|---|---|
| Read `bookmarks`, `follows`, `notifications`, `devices`, `reports`, `error_events` | 0 rows |
| Insert a tool, insert news | 401 |
| Insert bookmarks / follows / posts as a guest | 401 |
| Rename or delete a published tool | no rows affected |
| Escalate a profile to `admin` | no rows affected |
| Rename a category | no rows affected |

Afterwards the data was re-read to confirm nothing had changed: ChatGPT still
named correctly, 382 tools intact, all 10 categories intact, still exactly one
admin.

**Read HTTP 204 carefully.** PostgREST answers 204 for an UPDATE or DELETE that
matched zero rows, which is what RLS produces when a policy refuses. It looks
like success in a status column. Check the data, not the code.

`profiles` is readable by anyone by policy — display name, bio and role. That is
deliberate for a product with public reviews, but it is a choice, not an
oversight.

## Edge functions

Two classes, and they need opposite treatment.

### Ingestion — service role only

`fetch-news`, `fetch-tools`, `embed-tools`, `summarize-tools`. Each builds a
service-role client and then scrapes, embeds or calls an LLM.

**What was found:** none of them checked its caller. `fetch-news` answered 200
with no credentials at all; the other three answered 200 to the anon key. Anyone
could have run the scrapers and the Groq budget flat, and written to the
database through the service role, without an account.

**The fix** is `_shared/auth.ts`, one line at the top of each handler. It accepts
either an exact match against `SUPABASE_SERVICE_ROLE_KEY` or a JWT whose `role`
claim is `service_role`. Both paths are needed: this project carries both key
generations, and the newer `sb_secret_…` keys are opaque while the legacy ones
are JWTs. Checking only the first shape rejected pg_cron and CI — caught by
re-probing after the first deploy.

Reading the `role` claim without verifying the signature is safe **only** because
`verify_jwt = true` is set for these four in `supabase/config.toml`, so the
platform validates the signature first. If that is ever turned off, the claim
becomes forgeable and only the exact-key path still means anything.

Verified after deploy:

```
FUNCTION              no-auth   anon-key   service-role
fetch-news                401        401            200
fetch-tools               401        401            200
embed-tools               401        401            200
summarize-tools           401        401            200
```

### Removed: an open AI endpoint

`summarize` took a title and a description and ran them through the LLM, with
`verify_jwt = false` and no check of its own. Called with no credentials at all
on 26 September it returned three bullets about the text it was sent — so
anyone could use this project's Groq quota as a free, general-purpose model.
Nothing in Liz called it: the batch summariser uses the shared code directly.
It was missed in the first security pass because that probed a list of
functions written from memory. It is deleted, and the pass below is now run
against the list the live project reports.

### Every deployed function, probed

From `supabase functions list`, not from memory:

```
FUNCTION            no-auth  anon-key   what it is
fetch-news              401       401   ingestion — service role only
fetch-tools             401       401   ingestion — service role only
embed-tools             401       401   ingestion — service role only
summarize-tools         401       401   ingestion — service role only
send-notification       401       401   push — service role only
delete-account          401       401   needs the caller's own session
ask-liz                 400       400   public, 30 an hour per address
logo                    400       400   public, 300 a minute per address
tool-updates            401       400   public, 30 a minute per address
```

(400 is "you sent an empty body", which is the right answer to an empty probe.)

`send-notification` used to carry its own copy of the role check, which read
the JWT without restoring base64 padding and did not accept opaque keys. It now
uses `_shared/auth.ts` like the others; re-probed after deploying on 27
September with the same results, except that the anon key now gets 401 rather
than 403.

### Public by design — rate limited

`ask-liz` and `logo` have to stay anonymous: a visitor asks a question or loads
a page of logos without an account. But each ask-liz call runs an embedding
model and each logo call fetches an upstream image, so anonymous cannot also
mean unlimited.

- **ask-liz** — 30 per hour per address, counted in the `rate_limits` table via
  `take_rate_limit()`. One statement does the insert and the increment, so two
  simultaneous requests cannot both read the same count and both decide they
  were under.
- **logo** — 300 per minute per address, counted in memory. A page of the
  catalog fires dozens of logo requests and a database round trip on each one to
  save a favicon fetch would be a poor trade. Per instance, so it blunts a flood
  from one source rather than enforcing a global ceiling.

Verified: the 31st ask-liz call in an hour returns 429 with `Retry-After: 600`.

- **tool-updates** — 30 per minute per address, in memory. Every tool page asks
  for release notes, and each call spends part of GitHub's unauthenticated
  budget of 60 requests an hour, shared by everything this project runs from
  the same address. One caller looping over it would empty that budget and
  blank "What's new" for every visitor.

Both limiters **fail open**. A limiter that takes the feature down when the
database hiccups causes a worse outage than the abuse it guards against, and
what is being protected here is a bill, not data.

`x-forwarded-for` is spoofable by anyone willing to set a header, so this is a
cost ceiling rather than an access control. It stops a script left running, not
a determined attacker. What protects against those is that neither function can
write anything.

## Other surfaces

- **The logo proxy** refuses private address ranges, cloud metadata endpoints,
  non-image content types and responses over 5 MB. Covered by
  `tests/logo_logic_test.ts`.
- **No secret appears** in the repository or the client bundle. `.gitignore`
  covers `.env` files, keystores and `key.properties`.
- **XSS** is largely structural: Flutter renders `Text`, not HTML, so scraped
  content cannot execute. Scraped HTML is stripped at ingest regardless.
- **Service-role key handling.** It exists in three places: the Supabase runtime,
  a GitHub Actions secret, and Vault for pg_cron. It never reaches the client.

## Reporting

`reports` is written directly by the app under RLS. The `handle_report` trigger
hides a post, review or comment once enough people report it.

**What was found:** it counted reports, not reporters, and nothing stopped one
person reporting the same thing again. Verified on production with throwaway
accounts: one reported a review three times and it went from `active` to
`hidden`. Reviews appear on every tool page, so any signed-up user could take
down any review — and with email confirmation off, signing up costs nothing.

**Now (migration 0034):**

- One report per person per target, enforced by a unique constraint. A repeat
  returns `23505`, which the app treats as "already reported" rather than an
  error. An upsert would have been neater and does not work here: `ON CONFLICT`
  has to read the existing row, only moderators may read reports, so every
  report would have been refused — measured, before it shipped.
- Auto-hide needs three *distinct* reporters whose accounts are at least a day
  old. Reports from new accounts are still filed and still reach moderators;
  they cannot take something down by themselves.
- A reason is capped at 500 characters in the table. The removed `report`
  function applied that cap, but the app never called it, so it had never
  applied to anything.

Verified afterwards: repeats get `409`, three brand-new accounts cannot hide a
review, a 5,000-character reason is refused, and three established accounts
still can hide one — a moderation rule that never fires is broken too.

**Moderation queue.** Hide used to act on posts only; on a reported review it
quietly dismissed the report instead, so a moderator could believe something
was gone while it stayed live. It now works for posts, reviews, comments and
tools, shows what was reported instead of a UUID, and lists everything currently
hidden with a Restore button.

## Accounts

### Deletion

`delete-account` identifies the caller from their own JWT and removes the auth
user with the service role; every table cascades from `profiles`.

It had never been run until 26 September, and it failed for anyone who had used
the product. A new account deleted fine; one that had bookmarked a single tool
returned `Database error deleting user`. Every foreign key already cascaded —
the cascade itself was failing. Deleting an auth user runs as
`supabase_auth_admin`, the cascade reaches `bookmarks`, `likes`, `reviews` or
`comments`, and each fires a counter trigger that updates `tools` or `posts`.
Those four trigger functions had no `security definer`, so they ran as the role
doing the delete, which has no rights in the public schema, and the whole
transaction rolled back.

Migration 0033 gives them definer rights with a pinned `search_path`. They only
adjust a counter on the row the trigger names and run no caller-supplied SQL.
Verified: an account with a bookmark and a follow deletes cleanly, both rows go
with it, and the tool's `save_count` goes back down rather than staying inflated.

### Password reset

`/forgot-password` asks for an address and always answers the same way — "if
this address has an account, a link is on its way" — whether or not it does. A
reset form that says "no account found" is a way to find out who has one. Only a
rate-limit refusal is passed back, because it says nothing about the address.

The link returns to `/#/reset-password`, built from the running origin so one
build works locally and deployed. That address has to be on the allowlist under
Authentication → URL Configuration, or Supabase silently sends the reader to the
project's default site instead.

### Expired sessions

A token that expires or is revoked while the tab sits open now opens the sign-in
sheet with "Your session expired", signs the dead session out first so the retry
does not fail the same way, and retries the action. Row-level-security refusals
(`42501`) are deliberately *not* treated as expiry — signing in again cannot fix
them, and treating them as expiry would send someone round a loop.

## Still open

- **No SMTP provider.** Reset links, magic links and confirmation emails are all
  built and tested but cannot actually be delivered. Email confirmation stays off
  until a provider is configured.
- **Google and Apple sign-in are disabled** on the live project; only email works.
- **`site_url` still points at `localhost:3000`**, which will misdirect every auth
  email the moment this is deployed.
