# Stores a new Supabase database password in the two GitHub secrets that use
# it, after a reset in the dashboard (Project Settings -> Database -> Reset
# database password):
#
#   SUPABASE_DB_PASSWORD  deploy-supabase.yml (migrations)
#   SUPABASE_DB_URL       backup-db.yml (the Session pooler URI, password
#                         percent-encoded: an @ or / in it would otherwise
#                         break the URI, as happened on 5 October 2026)
#
# The password is typed at a hidden prompt and handed to `gh secret set` on
# standard input, so it never appears on screen, in the command history or in
# a process's arguments.
#
#   powershell -ExecutionPolicy Bypass -File tool\set-db-secrets.ps1

$ErrorActionPreference = 'Stop'
# Windows PowerShell pipes text to programs as ASCII by default, which would
# turn any non-ASCII character of the password into '?'.
$OutputEncoding = New-Object System.Text.UTF8Encoding $false
$ref = 'yluabeijvbydxczfxclk'
$pooler = 'aws-0-ap-south-1.pooler.supabase.com:5432'

$secure = Read-Host -AsSecureString 'Paste the new database password (hidden), then press Enter'
$plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
if ([string]::IsNullOrWhiteSpace($plain)) { throw 'No password entered; nothing changed.' }

try {
    $plain | gh secret set SUPABASE_DB_PASSWORD
    if ($LASTEXITCODE -ne 0) { throw 'Could not set SUPABASE_DB_PASSWORD.' }
    $encoded = [uri]::EscapeDataString($plain)
    "postgresql://postgres.${ref}:${encoded}@${pooler}/postgres" | gh secret set SUPABASE_DB_URL
    if ($LASTEXITCODE -ne 0) { throw 'Could not set SUPABASE_DB_URL.' }
    Write-Host 'Both secrets updated: SUPABASE_DB_PASSWORD and SUPABASE_DB_URL.'
} finally {
    $plain = $null; $encoded = $null
}
