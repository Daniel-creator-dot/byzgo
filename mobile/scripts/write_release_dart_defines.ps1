# Merge mobile/release_defines.json + maps key into dart_defines.json for Play/release builds.
param(
  [string]$ApiUrl = "https://www.bytzgo.net",
  [string]$MobileRoot = ""
)

$ErrorActionPreference = "Stop"
if (-not $MobileRoot) {
  $MobileRoot = Split-Path $PSScriptRoot -Parent
}
$repoRoot = Resolve-Path (Join-Path $MobileRoot "..")
$releaseFile = Join-Path $MobileRoot "release_defines.json"
$definesFile = Join-Path $MobileRoot "dart_defines.json"
$envFile = Join-Path $repoRoot ".env.local"
$defaultClient = "645977332644-4gjjf08268b3irafs4bh8b7guct1i1jb.apps.googleusercontent.com"

function Read-EnvValue([string]$name) {
  if (-not (Test-Path $envFile)) { return $null }
  foreach ($line in Get-Content $envFile) {
    $t = $line.Trim()
    if ($t -match "^\s*$name\s*=\s*(.+)\s*$") {
      return $Matches[1].Trim().Trim('"').Trim("'")
    }
  }
  return $null
}

$defines = @{
  GOOGLE_MAPS_API_KEY = ""
  API_URL = $ApiUrl.TrimEnd("/")
  GOOGLE_WEB_CLIENT_ID = $defaultClient
}

if (Test-Path $releaseFile) {
  $base = Get-Content $releaseFile -Raw | ConvertFrom-Json
  if ($base.API_URL) { $defines.API_URL = $base.API_URL.ToString().TrimEnd("/") }
  if ($base.GOOGLE_WEB_CLIENT_ID) { $defines.GOOGLE_WEB_CLIENT_ID = $base.GOOGLE_WEB_CLIENT_ID }
}

$mapsDart = Join-Path $MobileRoot "lib\core\maps_key.dart"
if (Test-Path $mapsDart) {
  $raw = Get-Content $mapsDart -Raw
  if ($raw -match "resolved = '([^']+)'") {
    $defines.GOOGLE_MAPS_API_KEY = $Matches[1]
  }
}

$client = Read-EnvValue "GOOGLE_WEB_CLIENT_ID"
if (-not $client) { $client = Read-EnvValue "VITE_GOOGLE_CLIENT_ID" }
if ($client) { $defines.GOOGLE_WEB_CLIENT_ID = $client }

if (-not $defines.GOOGLE_WEB_CLIENT_ID) {
  throw "GOOGLE_WEB_CLIENT_ID missing - check release_defines.json"
}

$json = ($defines | ConvertTo-Json -Depth 3)
[System.IO.File]::WriteAllText($definesFile, $json)
Write-Host "Wrote dart_defines.json for release (API_URL=$($defines.API_URL))"
Write-Host "  GOOGLE_WEB_CLIENT_ID=$($defines.GOOGLE_WEB_CLIENT_ID.Substring(0, [Math]::Min(24, $defines.GOOGLE_WEB_CLIENT_ID.Length)))..."
