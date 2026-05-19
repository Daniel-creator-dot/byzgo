# Run analyzer and unit tests (requires Flutter on PATH).
$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)

$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) {
    Write-Error "Flutter not on PATH. Install from https://docs.flutter.dev/get-started/install/windows"
}

& flutter pub get
& flutter analyze
& flutter test
Write-Host "All checks passed." -ForegroundColor Green
