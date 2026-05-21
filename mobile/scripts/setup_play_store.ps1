# One-shot Play Store prep: upload keystore (if missing), SHA-1 hint, signed AAB.
# Usage (repo root): npm run play:setup
# Or: cd mobile && .\scripts\setup_play_store.ps1

$ErrorActionPreference = "Stop"
$mobileRoot = Split-Path $PSScriptRoot -Parent
$androidDir = Join-Path $mobileRoot "android"
$keystore = Join-Path $androidDir "upload-keystore.jks"
$keyProps = Join-Path $androidDir "key.properties"

if (-not (Test-Path $keystore)) {
  Write-Host "=== Creating upload keystore ===" -ForegroundColor Cyan
  & (Join-Path $PSScriptRoot "create_upload_keystore.ps1") -NonInteractive
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} else {
  Write-Host "Upload keystore exists." -ForegroundColor Green
}

if (-not (Test-Path $keyProps)) {
  Write-Host "Missing key.properties - copy from key.properties.example" -ForegroundColor Red
  exit 1
}

Write-Host ""
Write-Host "=== Release certificate (add to Firebase + Google Cloud) ===" -ForegroundColor Cyan
& (Join-Path $PSScriptRoot "print_release_sha1.ps1")

Write-Host ""
Write-Host "=== Building signed App Bundle ===" -ForegroundColor Cyan
& (Join-Path $PSScriptRoot "build_aab.ps1")
exit $LASTEXITCODE
