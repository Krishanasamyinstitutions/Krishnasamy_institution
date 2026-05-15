# Wire up Edge Functions (link + secrets + deploy) against a fresh
# Supabase project in one shot.
#
# Usage:
#   pwsh -ExecutionPolicy Bypass -File scripts\bootstrap_new_supabase.ps1 `
#        -ProjectRef abcdefghijklmnop
#
#   Optional flags:
#     -SkipLink     don't run `supabase link` (already linked)
#     -SkipSecrets  don't push secrets (already set)
#     -SkipDeploy   don't deploy functions
#
# This script does NOT:
#   • Apply the SQL schema. Run C:\pg_backups\complete_setup.sql in the
#     Supabase SQL Editor (or via psql) before invoking this — Edge
#     Functions that hit the DB (e.g. request-product-license) need the
#     tables and RPCs created first.
#   • Update lib/config/supabase_config.dart. Paste the new project URL
#     and anon key there by hand before building the Flutter app.

param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRef,
    [switch]$SkipLink,
    [switch]$SkipSecrets,
    [switch]$SkipDeploy
)

$ErrorActionPreference = 'Stop'

$cli = (Get-Command supabase -ErrorAction SilentlyContinue)
if ($null -ne $cli) {
    $supabase = { param($args) & supabase @args }
} else {
    Write-Host 'supabase CLI not on PATH; falling back to `npx supabase`.' -ForegroundColor Yellow
    $supabase = { param($args) & npx --yes supabase @args }
}

$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    if (-not $SkipLink) {
        Write-Host ('==> Linking Supabase project {0}' -f $ProjectRef) -ForegroundColor Cyan
        & $supabase @('link', '--project-ref', $ProjectRef)
        if ($LASTEXITCODE -ne 0) { throw 'supabase link failed' }
        Write-Host ''
    }

    if (-not $SkipSecrets) {
        $envFile = Join-Path $PSScriptRoot 'secrets.env'
        if (-not (Test-Path $envFile)) {
            Write-Host ''
            Write-Host ('Missing {0}.' -f $envFile) -ForegroundColor Red
            Write-Host 'Copy secrets.env.example to secrets.env and fill in real values, then re-run with -SkipLink.' -ForegroundColor Red
            exit 1
        }
        Write-Host '==> Pushing secrets' -ForegroundColor Cyan
        & (Join-Path $PSScriptRoot 'set_secrets.ps1')
        if ($LASTEXITCODE -ne 0) { throw 'set_secrets.ps1 failed' }
        Write-Host ''
    }

    if (-not $SkipDeploy) {
        Write-Host '==> Deploying Edge Functions' -ForegroundColor Cyan
        & (Join-Path $PSScriptRoot 'deploy_functions.ps1')
        if ($LASTEXITCODE -ne 0) { throw 'deploy_functions.ps1 failed' }
        Write-Host ''
    }

    Write-Host 'Bootstrap complete.' -ForegroundColor Green
    Write-Host ''
    Write-Host 'Still left to do by hand:' -ForegroundColor Yellow
    Write-Host '  • Run C:\pg_backups\complete_setup.sql in Supabase SQL Editor.'
    Write-Host '  • Update lib/config/supabase_config.dart with the new project url + anonKey.'
    Write-Host '  • `flutter pub get` and rebuild the app.'
} finally {
    Pop-Location
}
