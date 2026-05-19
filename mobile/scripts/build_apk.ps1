# Build a release APK with API URL + Maps key baked in (for physical devices).
# Usage:
#   .\scripts\build_apk.ps1
#   .\scripts\build_apk.ps1 -ApiUrl "https://your-api.onrender.com"
#
# Reads MOBILE_API_URL (or VITE_API_URL) from repo .env.local when -ApiUrl is omitted.

param(
  [string]$ApiUrl = ""
)

$ErrorActionPreference = "Stop"
$mobileRoot = Split-Path $PSScriptRoot -Parent
$repoRoot = Resolve-Path (Join-Path $mobileRoot "..")
$envFile = Join-Path $repoRoot ".env.local"
$definesFile = Join-Path $mobileRoot "dart_defines.json"

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

if (-not $ApiUrl) {
  $ApiUrl = Read-EnvValue "MOBILE_API_URL"
}
if (-not $ApiUrl) {
  $ApiUrl = Read-EnvValue "VITE_API_URL"
}
# Production default: same host as Render web+API (bytzgo.net)
if (-not $ApiUrl) {
  $ApiUrl = "https://bytzgo.net"
}

$ApiUrl = $ApiUrl.TrimEnd("/")
Write-Host "BytzGo APK - API_URL=$ApiUrl"

& (Join-Path $PSScriptRoot "sync_maps_key.ps1")

$defines = @{
  GOOGLE_MAPS_API_KEY = ""
  API_URL = $ApiUrl
  GOOGLE_WEB_CLIENT_ID = ""
}
if (Test-Path $definesFile) {
  try {
    $existing = Get-Content $definesFile -Raw | ConvertFrom-Json
    if ($existing.GOOGLE_MAPS_API_KEY) { $defines.GOOGLE_MAPS_API_KEY = $existing.GOOGLE_MAPS_API_KEY }
    if ($existing.GOOGLE_WEB_CLIENT_ID) { $defines.GOOGLE_WEB_CLIENT_ID = $existing.GOOGLE_WEB_CLIENT_ID }
  } catch { }
}
$client = Read-EnvValue "GOOGLE_WEB_CLIENT_ID"
if (-not $client) { $client = Read-EnvValue "VITE_GOOGLE_CLIENT_ID" }
if ($client) { $defines.GOOGLE_WEB_CLIENT_ID = $client }

$json = ($defines | ConvertTo-Json -Depth 3)
[System.IO.File]::WriteAllText($definesFile, $json)
Write-Host "Wrote dart_defines.json (API_URL set for device install)"

$flutter = Join-Path $repoRoot ".flutter-sdk\bin\flutter.bat"
if (-not (Test-Path $flutter)) {
  $flutter = "flutter"
}

Push-Location $mobileRoot
try {
  & $flutter pub get
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  & $flutter build apk --release --dart-define-from-file=dart_defines.json
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
  Pop-Location
}

$apk = Join-Path $mobileRoot "build\app\outputs\flutter-apk\app-release.apk"
Write-Host ""
Write-Host "APK ready:" -ForegroundColor Green
Write-Host "  $apk"
Write-Host "Copy to your phone and install, or: adb install $apk"
