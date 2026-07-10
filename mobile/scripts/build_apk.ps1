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
# Production default: www avoids Render 307 apex→www redirect on POST (Dio login).
if (-not $ApiUrl) {
  $ApiUrl = "https://www.bytzgo.net"
}

$ApiUrl = $ApiUrl.TrimEnd("/")
Write-Host "BytzGo APK - API_URL=$ApiUrl"

& (Join-Path $PSScriptRoot "sync_maps_key.ps1")
& (Join-Path $PSScriptRoot "write_release_dart_defines.ps1") -ApiUrl $ApiUrl -MobileRoot $mobileRoot

$flutter = Join-Path $repoRoot ".flutter-sdk\bin\flutter.bat"
if (-not (Test-Path $flutter)) {
  $flutter = "flutter"
}

$sideloadProps = Join-Path $mobileRoot "android\sideload-signing.properties"
$sideloadJks = Join-Path $mobileRoot "android\bytzgo-sideload.jks"
$keyProps = Join-Path $mobileRoot "android\key.properties"
if ((Test-Path $sideloadProps) -and (Test-Path $sideloadJks)) {
  Copy-Item $sideloadProps $keyProps -Force
  Write-Host "BytzGo: signing APK with bytzgo-sideload.jks (Google Sign-In)" -ForegroundColor Cyan
} else {
  Write-Host "BytzGo: WARNING - bytzgo-sideload.jks missing; Google Sign-In may fail (error 10)" -ForegroundColor Yellow
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
$copyScript = Join-Path $repoRoot "scripts\copy-apk-to-public.mjs"
if (Test-Path $copyScript) {
  node $copyScript
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
Write-Host ""
Write-Host "APK ready:" -ForegroundColor Green
Write-Host "  $apk"
Write-Host "  public/bytzgo.apk (for https://www.bytzgo.net/download/android after deploy)"
Write-Host "Copy to your phone and install, or: adb install $apk"
Write-Host "For Google Play use: npm run flutter:build:aab (see docs/PLAY_STORE.md)"
