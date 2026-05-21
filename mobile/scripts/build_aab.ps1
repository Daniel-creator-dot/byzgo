# Build a signed release App Bundle (.aab) for Google Play.
# Requires android/key.properties + upload-keystore.jks (see create_upload_keystore.ps1).

param(
  [string]$ApiUrl = ""
)

$ErrorActionPreference = "Stop"
$mobileRoot = Split-Path $PSScriptRoot -Parent
$repoRoot = Resolve-Path (Join-Path $mobileRoot "..")
$envFile = Join-Path $repoRoot ".env.local"
$definesFile = Join-Path $mobileRoot "dart_defines.json"
$keyProps = Join-Path $mobileRoot "android\key.properties"

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

if (-not (Test-Path $keyProps)) {
  Write-Host "Missing android/key.properties - Play requires a release upload key." -ForegroundColor Red
  Write-Host "  cd mobile"
  Write-Host "  .\scripts\create_upload_keystore.ps1"
  Write-Host "  Copy android\key.properties.example -> android\key.properties and set passwords."
  exit 1
}

if (-not $ApiUrl) {
  $ApiUrl = Read-EnvValue "MOBILE_API_URL"
}
if (-not $ApiUrl) {
  $ApiUrl = Read-EnvValue "VITE_API_URL"
}
if (-not $ApiUrl) {
  $ApiUrl = "https://www.bytzgo.net"
}
$ApiUrl = $ApiUrl.TrimEnd("/")
Write-Host "BytzGo AAB - API_URL=$ApiUrl"

& (Join-Path $PSScriptRoot "sync_maps_key.ps1")
& (Join-Path $PSScriptRoot "write_release_dart_defines.ps1") -ApiUrl $ApiUrl -MobileRoot $mobileRoot

$flutter = Join-Path $repoRoot ".flutter-sdk\bin\flutter.bat"
if (-not (Test-Path $flutter)) { $flutter = "flutter" }

$localProps = Join-Path $mobileRoot "android\local.properties"
if (Test-Path $localProps) {
  Get-Content $localProps | ForEach-Object {
    if ($_ -match '^\s*sdk\.dir\s*=\s*(.+)\s*$') {
      $sdk = $Matches[1].Trim().Replace('\\', '\')
      $env:ANDROID_HOME = $sdk
      $env:ANDROID_SDK_ROOT = $sdk
    }
  }
}

Push-Location $mobileRoot
try {
  & $flutter pub get
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  & $flutter build appbundle --release --dart-define-from-file=dart_defines.json
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
  Pop-Location
}

$aab = Join-Path $mobileRoot "build\app\outputs\bundle\release\app-release.aab"
Write-Host ""
Write-Host "App Bundle ready for Play Console:" -ForegroundColor Green
Write-Host "  $aab"
Write-Host ""
Write-Host 'Upload in Play Console: Release - Production - Create release - Upload AAB'
