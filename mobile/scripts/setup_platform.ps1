# Generates or refreshes android/ and ios/ (requires Flutter SDK on PATH).
$ErrorActionPreference = "Stop"
$mobileRoot = Split-Path -Parent $PSScriptRoot

Set-Location $mobileRoot

$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) {
    Write-Host ""
    Write-Host "Flutter not found on PATH." -ForegroundColor Yellow
    Write-Host "  1. Install: https://docs.flutter.dev/get-started/install/windows" -ForegroundColor Gray
    Write-Host "  2. Add flutter\bin to PATH, then re-run this script." -ForegroundColor Gray
    Write-Host ""
    Write-Host "A minimal android/ template is included; run 'flutter create .' when Flutter is installed" -ForegroundColor Gray
    Write-Host "to complete ios/ and refresh platform files." -ForegroundColor Gray
    exit 1
}

Write-Host "Flutter: $($flutter.Source)"
& flutter --version

if (-not (Test-Path "android")) {
    Write-Host "Creating platform projects..."
    & flutter create . --org com.bytzgo --project-name bytzgo_mobile
} else {
    Write-Host "Platform folders exist — syncing..."
    & flutter create . --org com.bytzgo --project-name bytzgo_mobile
}

& flutter pub get

if (Test-Path ".\scripts\sync_maps_key.ps1") {
    Write-Host ""
    Write-Host "Syncing Google Maps API key from repo .env.local..."
    & .\scripts\sync_maps_key.ps1
}

Write-Host ""
Write-Host "Done. Next steps:" -ForegroundColor Green
Write-Host "  - flutter run --dart-define-from-file=dart_defines.json --dart-define=API_URL=http://10.0.2.2:3000"
Write-Host "  - Optional: flutterfire configure (Google Sign-In)"
