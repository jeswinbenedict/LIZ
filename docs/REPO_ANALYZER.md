# Repository Analyzer

Paste a GitHub repository; Liz reads it and explains how it was built — the
stack, the architecture, the data, the API, build and deployment — in a
23-section report with diagrams, a code explorer, and answers to questions
grounded in the repository's own files. In the app: **Repos** in the
navigation (`/repos`, a report at `/repos/:id`).

## What can be pasted

Whatever GitHub's **Code → Clone** box gives, all leading to the same
analysis:

| Tab | Example |
|---|---|
| HTTPS | `https://github.com/owner/name.git` (or the page address, with or without `/tree/<branch>`) |
| SSH | `git@github.com:owner/name.git`, or `ssh://git@github.com/owner/name.git` |
| GitHub CLI | `gh repo clone owner/name` (a directory or `-- flags` after it are ignored) |

Also `owner/name` on its own and a whole `git clone … <url> …` command. The
form is recognised by `parseRepoUrl` (`_shared/repo/url.ts`); the app checks
the same shapes before sending. Every form names the same repository, so
none is "cloned" differently: Liz reads the repository through GitHub's API
in every case, which needs no SSH key and never runs anything.

## How it works

```
App (/repos)                 analyze-repo (Edge Function)              GitHub
  paste URL ──────────────▶  check caller (Firebase token → Liz uid)
                             parse URL, rate limit (10/hour/person)
                             resolve repo + commit ───────────────────▶ REST API
                             reused public commit? copy it, done
                             insert repo_analyses row (running)
  ◀── { id } ──────────────  respond; keep working in the background
  poll the row ◀── progress  list tree (Git Trees API, recursive) ─────▶
                             choose ≤180 files, ≤3 MB (select.ts)
                             read them (raw.githubusercontent, or the
                               API with a token; unchanged blobs reused)
                             redact secrets (secrets.ts)
                             manifests → dependencies → technologies
                             routes, schema, settings, CI, containers,
                               deploy targets, entry points, imports
                             modules + diagrams (architecture.ts)
                             23 sections (report.ts)
                             AI overview from the facts only (narrate.ts)
                             save report + files; status done
  open report ◀──────────── repo_analyses / repo_analysis_files (RLS)
  Ask ────────────────────▶ ask-repo: owner check, retrieve excerpts,
                             model answers with [path:line] citations
```

Code: `supabase/functions/_shared/repo/` (engine, pure and tested),
`supabase/functions/analyze-repo` and `ask-repo` (thin handlers),
`supabase/migrations/0064_repo_analyses.sql`, `lib/features/repo_analyzer/`.

## Evidence, not invention

- **Technologies** are matched by rule (`detect.ts`): a declared dependency or
  a configuration file that only exists for it makes one *confirmed*; a
  mention in code alone makes it *inferred*, and the report says so.
- **Endpoints** are route declarations (Express/Koa/Fastify/Hono, NestJS,
  Next.js route handlers and API routes, Supabase Edge Functions, FastAPI,
  Flask, Django, Spring, Go, Rails, OpenAPI files), each with file and line.
- **Tables** are `CREATE TABLE`s, Prisma models, Django/SQLAlchemy/SQLModel
  tables, Mongoose/TypeORM/Drizzle models; relationships are foreign keys and
  relation fields.
- **Diagrams** only have nodes for what was found, and each node lists the
  files that show it. A section with nothing found says so.

## Security

- **Repository code is never run.** It is read as text and matched with
  patterns; nothing is executed, imported or evaluated.
- **Secrets**: every file is scanned before anything is kept (providers'
  published key formats, private keys, connection strings with real
  passwords, hard-coded `password = "…"` outside tests). Values are replaced
  with `[REDACTED]` in the stored copy and the report lists where they were.
  Files likely to *be* secrets (`.env`, `*.pem`, `credentials.json`…) are
  never read; a committed `.env` is reported by name. Firebase web API keys
  are noted as public by design.
- **Prompt injection**: the AI overview sees only extracted facts, never raw
  files. Ask sends fenced, numbered excerpts that the system prompt labels as
  untrusted data; the model has no tools, and citations to anything it was
  not shown are dropped.
- **Access**: rows and stored files are readable only by their owner (RLS on
  `current_uid()`); only the functions (service role) write. A private
  repository's files are never reused for anyone else.
- **Tokens** for private repositories are used for that one request and
  background run, then dropped: never stored, logged or returned, and never
  in an error message.
- **Limits**: 10 analyses an hour per person (and per address), 40 questions
  an hour per person.

## Efficiency

- A public commit analysed in the last 30 days is copied, not re-read.
- A file whose Git blob SHA was read before (a public repository, or this
  person's own earlier run of the same private one) is not fetched again —
  re-analysing after a few commits only fetches what changed.
- Public file contents come from raw.githubusercontent.com, which does not
  spend the API's 60-an-hour anonymous allowance.

## Limits

- Up to 180 files and 3 MB are read per analysis, chosen by how much they
  explain (manifests, CI, docs, schemas, entry points, routes, then source,
  shallowest first). Huge monorepos are described from that sample; the file
  tree itself is complete up to 8,000 files (GitHub truncates beyond ~100,000
  entries).
- Detection is by pattern: frameworks without a rule are not named, and an
  unusual routing style can be missed. Inferred results are marked.
- Vulnerability advisories are not looked up (no free, reliable source
  without an API key); the report flags missing lock files and automated
  dependency updates instead.
- Private repositories need a token pasted for each run; there is no GitHub
  OAuth app (that would need the owner to register one).
- Ask and the AI overview need `AI_API_KEY` (docs/OPERATIONS.md). Without it,
  the report is complete and Ask says the AI is unavailable.

## Running the tests

```bash
deno test --allow-env --no-check supabase/functions/tests/repo_analyzer_test.ts
flutter test test/repo_analyzer_test.dart
```
