# Run Liz in Chrome against the Supabase project configured in .env.
#
# Copy .env.example to .env and fill in your project's URL and anon key
# (public, client-side values). Without .env the app runs on demo data.
# NEVER put the service-role key or the database password in .env: it is
# compiled into the web bundle.

if (Test-Path .env) {
  flutter run -d chrome --dart-define-from-file=.env
} else {
  Write-Host 'No .env found: running on bundled demo data.'
  flutter run -d chrome
}
