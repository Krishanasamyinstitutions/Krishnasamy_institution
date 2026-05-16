# Push Supabase Edge Function secrets from a local env file.
#
# Usage:
#   1. Copy scripts\secrets.env.example to scripts\secrets.env
#   2. Fill in real values in scripts\secrets.env (NEVER commit this file)
#   3. pwsh -ExecutionPolicy Bypass -File scripts\set_secrets.ps1
#
# Lines starting with '#' or blank are skipped. Empty values are skipped
# (they would clear the secret on Supabase — usually unintended).

$ErrorActionPreference = 'Stop'

$cli = (Get-Command supabase -ErrorAction SilentlyContinue)
if ($null -ne $cli) {
    $supabase = { param($args) & supabase @args }
} else {
    Write-Host 'supabase CLI not on PATH; falling back to `npx supabase`.' -ForegroundColor Yellow
    $supabase = { param($args) & npx --yes supabase @args }
}

$root = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $PSScriptRoot 'secrets.env'

if (-not (Test-Path $envFile)) {
    Write-Host ("Missing $envFile. Copy secrets.env.example to secrets.env and fill in real values.") -ForegroundColor Red
    exit 1
}

Push-Location $root
try {
    $pairs = @()
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith('#')) { return }
        $eq = $line.IndexOf('=')
        if ($eq -lt 1) { return }
        $key = $line.Substring(0, $eq).Trim()
        $val = $line.Substring($eq + 1).Trim()
        if ($val.StartsWith('"') -and $val.EndsWith('"')) {
            $val = $val.Substring(1, $val.Length - 2)
        }
        if ([string]::IsNullOrEmpty($val)) {
            Write-Host ("Skipping {0} (empty value)" -f $key) -ForegroundColor Yellow
            return
        }
        $pairs += [PSCustomObject]@{ Key = $key; Value = $val }
    }

    if ($pairs.Count -eq 0) {
        Write-Host 'No secrets to set (env file was empty or all values blank).' -ForegroundColor Yellow
        exit 0
    }

    Write-Host ('Setting {0} secret(s):' -f $pairs.Count) -ForegroundColor Cyan
    foreach ($p in $pairs) { Write-Host ('  - ' + $p.Key) }
    Write-Host ''

    $args = @('secrets', 'set')
    foreach ($p in $pairs) {
        $args += ("{0}={1}" -f $p.Key, $p.Value)
    }
    & $supabase $args
    if ($LASTEXITCODE -ne 0) {
        throw 'supabase secrets set failed'
    }

    Write-Host ''
    Write-Host 'Secrets pushed to Supabase project.' -ForegroundColor Green
} finally {
    Pop-Location
}
