# Contributing to Liz

Thank you for taking the time to help. This guide covers how to set up the
project, the checks a change has to pass, and how to send it.

## Before you start

- For a bug, open an issue with the bug report template first, unless the fix
  is small and obvious.
- For a feature, open an issue with the feature request template and describe
  the problem before writing code. Some directions are deliberately closed
  (see "Deliberate decisions" in the README): no paid AI APIs, web first.
- Never report a security problem in a public issue. See [SECURITY.md](SECURITY.md).

## Setting up

The app runs on bundled demo data with no accounts or keys:

```bash
flutter pub get
flutter run -d chrome
```

To work against your own backend, see "Local development" in the
[README](README.md#local-development). You never need the maintainer's
Supabase or Firebase projects to contribute.

## The checks

CI runs these on every pull request. Run the ones that cover your change
before pushing:

```bash
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze            # clean at every level, infos included
flutter test
cd scrapers && python -m pytest tests && cd ..
ruff check scrapers tool --config scrapers/pyproject.toml
deno test --allow-env --no-check supabase/functions/tests
```

`tool/ci_local.sh` runs all of them, plus the browser journeys and the
accessibility audit ([tool/qa/README.md](tool/qa/README.md)).
`git config core.hooksPath tool/hooks` runs the fast ones before every push.

## Conventions

- **Commits** follow `type(scope): what changed, in plain words`, for
  example `fix(auth): keep the session when a token refresh fails`. Types in
  use: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `ci`, `chore`.
- **Tests.** A behaviour change comes with a test. Edge Function decisions
  live in `logic.ts` files so their tests need no network. A new screen goes
  into `test/screen_sweep_test.dart`, which checks it at phone and tablet
  sizes, at 1.5x text and against Flutter's accessibility guidelines.
- **Design.** UI follows [docs/DESIGN.md](docs/DESIGN.md).
- **Database.** Schema changes are new numbered files in
  `supabase/migrations/`, never edits to applied ones. Every new table enables
  row-level security, with its policies in the same migration.
- **Secrets.** Never commit keys, tokens, passwords, `.env` files or database
  dumps. CI scans every change for secrets.

## Pull requests

1. Fork the repository and branch from `main`.
2. Make the change, with tests and documentation where it applies.
3. Run the checks above.
4. Open a pull request and fill in the template.

By contributing you agree that your contribution is licensed under the
Apache License 2.0, as stated in section 5 of the [LICENSE](LICENSE).

Everyone taking part is expected to follow the
[Code of Conduct](CODE_OF_CONDUCT.md).
