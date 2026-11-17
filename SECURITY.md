# Security Policy

## Reporting a vulnerability

**Please do not report security vulnerabilities in public issues, pull
requests or discussions.**

Report them privately through GitHub: **Security → Report a vulnerability**
on this repository
(<https://github.com/jeswinbenedict/LIZ/security/advisories/new>).

Please include:

- what is affected (a screen, an Edge Function, a policy, a workflow);
- the steps to reproduce it, or a proof of concept;
- the impact you expect.

You can expect an acknowledgement within 7 days and an assessment within
14 days. Fixes ship as soon as they are ready, and you will be credited in
the advisory unless you ask not to be.

## Supported versions

Only the `main` branch, which is what is deployed, receives security fixes.
There are no versioned releases.

## Scope

In scope: this repository's code, database migrations and row-level security
policies, Edge Functions, and GitHub Actions workflows.

Out of scope: the third-party services themselves (Supabase, Firebase,
Cloudflare, Groq), findings that need an already compromised device or
browser, missing best practices with no demonstrated impact, and volumetric
denial of service.

Please do not run automated scanners against the live deployment, access or
change other people's data, or degrade the service while testing. Test
against your own Supabase project (README, "Local development").

## How the project is secured

[docs/SECURITY.md](docs/SECURITY.md) describes the model in detail: why the
Supabase anon key and the Firebase web configuration are public by design,
how row-level security protects every table, how each Edge Function
authenticates and is rate limited, and the problems found and fixed so far.
