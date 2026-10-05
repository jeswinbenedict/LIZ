# Starts the self-hosted n8n that runs Liz's scraper from this machine.
#
#   powershell -ExecutionPolicy Bypass -File n8n\start-n8n.ps1
#
# Everything it needs lives in ~/.liz, outside the repository (which OneDrive
# syncs): the n8n install, the scraper's Python environment, and the secrets
# file. See n8n/README.md for how each is created.

$ErrorActionPreference = 'Stop'
$liz = Join-Path $HOME '.liz'

# Secrets: SUPABASE_URL and LIZ_INGEST_KEY. The scraper reads them
# from the environment n8n passes to its commands.
$envFile = Join-Path $liz 'n8n.env'
if (-not (Test-Path $envFile)) { throw "Missing $envFile - see n8n/README.md" }
Get-Content $envFile | Where-Object { $_ -match '^\s*[A-Za-z_][A-Za-z0-9_]*\s*=' } | ForEach-Object {
    $name, $value = $_ -split '=', 2
    [Environment]::SetEnvironmentVariable($name.Trim(), $value.Trim(), 'Process')
}

# Where the commands run, and with which Python. Read by the Execute Command
# nodes through the shell (%LIZ_REPO_DIR%), not through n8n's $env, which n8n
# 2.x blocks in expressions - and should: it would expose the service key to
# every expression and Code node.
$env:LIZ_REPO_DIR = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$env:LIZ_PYTHON = Join-Path $liz 'scraper-venv\Scripts\python.exe'
if (-not (Test-Path $env:LIZ_PYTHON)) { throw "Missing $($env:LIZ_PYTHON) - see n8n/README.md" }

# Tool names are not all ASCII, and Windows pipes default to cp1252, which
# stops Python mid-run on the first one it cannot encode.
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'

# n8n 2.x switches Execute Command off by default; this workflow is built on it.
$env:NODES_EXCLUDE = '[]'

# A node that can run any command must not be reachable from the network.
$env:N8N_LISTEN_ADDRESS = '127.0.0.1'
$env:N8N_HOST = 'localhost'
$env:N8N_PORT = '5678'

# Nothing leaves this machine that does not need to.
$env:N8N_DIAGNOSTICS_ENABLED = 'false'
$env:N8N_VERSION_NOTIFICATIONS_ENABLED = 'false'
$env:N8N_PERSONALIZATION_ENABLED = 'false'

# n8n runs on Node 24, the LTS line it supports. One of its dependencies has
# no prebuilt binary for newer Node and would need a C++ toolchain, so a
# portable Node 24 in ~/.liz is used for n8n alone, leaving the system's own
# Node untouched.
$node = Join-Path $liz 'node24'
if (-not (Test-Path (Join-Path $node 'node.exe'))) { throw "Missing $node - see n8n/README.md" }
$env:PATH = "$node;$env:PATH"

$n8n = Join-Path $liz 'n8n\node_modules\.bin\n8n.cmd'
if (-not (Test-Path $n8n)) { throw "Missing $n8n - see n8n/README.md" }

if ($args.Count -gt 0) {
    # Pass-through for the CLI, e.g. `start-n8n.ps1 execute --id=<id>`.
    & $n8n @args
} else {
    & $n8n start
}
