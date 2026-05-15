# Deploy every Supabase Edge Function in `supabase/functions/` to the
# linked Supabase project. Run from the project root:
#
#   pwsh -ExecutionPolicy Bypass -File scripts\deploy_functions.ps1
#
# Prerequisites:
#   • Supabase CLI installed (`scoop install supabase` or
#     `npm install -g supabase`), OR npx will be used automatically.
#   • Project linked: `supabase link --project-ref <your-ref>` once.

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
    $functionsDir = Join-Path $root 'supabase\functions'
    if (-not (Test-Path $functionsDir)) {
        throw "Functions directory not found: $functionsDir"
    }

    $functions = Get-ChildItem $functionsDir -Directory |
                 Where-Object { Test-Path (Join-Path $_.FullName 'index.ts') }

    if ($functions.Count -eq 0) {
        Write-Host 'No Edge Functions found to deploy.' -ForegroundColor Yellow
        exit 0
    }

    Write-Host ('Deploying {0} Edge Function(s):' -f $functions.Count) -ForegroundColor Cyan
    foreach ($fn in $functions) { Write-Host ('  - ' + $fn.Name) }
    Write-Host ''

    foreach ($fn in $functions) {
        Write-Host ('==> Deploying {0}' -f $fn.Name) -ForegroundColor Cyan
        & $supabase @('functions', 'deploy', $fn.Name)
        if ($LASTEXITCODE -ne 0) {
            throw ('Deploy failed for ' + $fn.Name)
        }
    }

    Write-Host ''
    Write-Host 'All functions deployed.' -ForegroundColor Green
} finally {
    Pop-Location
}
