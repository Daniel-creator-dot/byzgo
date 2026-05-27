# Sync GOOGLE_MAPS_API_KEY into Android, iOS, and Dart (cross-platform).
# Delegates to sync_maps_key.mjs so Windows, macOS, and Linux share one implementation.
$ErrorActionPreference = "Stop"
$script = Join-Path $PSScriptRoot "sync_maps_key.mjs"
if (-not (Test-Path $script)) {
    Write-Error "Missing $script"
    exit 1
}
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host "Install Node.js (https://nodejs.org/), then re-run this script."
    Write-Host "Alternatively set GOOGLE_MAPS_API_KEY in the environment and run: node `"$script`""
    exit 1
}
& node $script
exit $LASTEXITCODE
