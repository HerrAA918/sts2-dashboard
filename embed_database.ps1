# embed_database.ps1
#
# Injects the compiled sts2_database.json into sts2_dashboard.html, replacing ONLY
# the region between the STS2_DATABASE_START / STS2_DATABASE_END markers.
#
# This is the data-update path for the dashboard. The dashboard's CSS / JS / markup
# is hand-maintained directly in sts2_dashboard.html and is intentionally NOT
# regenerated, so this script never touches anything outside the marker region.
#
# Usage:  pwsh ./embed_database.ps1   (run after compile_db.ps1 refreshes the DB)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$htmlPath = Join-Path $root 'sts2_dashboard.html'
$dbPath   = Join-Path $root 'sts2_database.json'

if (-not (Test-Path $htmlPath)) { throw "Not found: $htmlPath" }
if (-not (Test-Path $dbPath))   { throw "Not found: $dbPath" }

# Read both as UTF-8 explicitly. Windows PowerShell 5.1's Get-Content default
# encoding mangles multi-byte characters (emoji, en/em dashes, etc.), so go via
# .NET to stay correct on both Windows PS 5.1 and the CI's pwsh 7.
$utf8 = New-Object System.Text.UTF8Encoding $false
$html   = [System.IO.File]::ReadAllText($htmlPath, $utf8)
$dbJson = ([System.IO.File]::ReadAllText($dbPath, $utf8)).Trim()

# Fail loudly if the DB isn't valid JSON, so we never inject a broken database.
$null = $dbJson | ConvertFrom-Json

$startMarker = '/* STS2_DATABASE_START'
$endMarker   = '/* STS2_DATABASE_END */'

$startIdx = $html.IndexOf($startMarker)
$endIdx   = $html.IndexOf($endMarker)
if ($startIdx -lt 0 -or $endIdx -lt 0 -or $endIdx -le $startIdx) {
    throw "Database markers not found (or out of order) in sts2_dashboard.html"
}

# Preserve everything up to and including the START marker comment line,
# and everything from the END marker onward. Only the block between changes.
$startLineEnd = $html.IndexOf("`n", $startIdx)
if ($startLineEnd -lt 0) { throw "Malformed START marker line." }

$nl     = if ($html.Contains("`r`n")) { "`r`n" } else { "`n" }
$before = $html.Substring(0, $startLineEnd + 1)
$after  = $html.Substring($endIdx)

$newBlock = "        const sts2Database = " + $dbJson + ";" + $nl + "        "
$updated  = $before + $newBlock + $after

# Write UTF-8 without BOM, matching the existing file.
[System.IO.File]::WriteAllText($htmlPath, $updated, $utf8)
Write-Host "Embedded sts2_database.json into sts2_dashboard.html ($($dbJson.Length) chars)."
