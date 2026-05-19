# Opens Render Blueprint + checks API health until JSON is returned.
# You must sign in to Render in the browser when prompted (one time).

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$blueprintUrl = "https://dashboard.render.com/blueprint/new?repo=https://github.com/Daniel-creator-dot/byzgo"

Write-Host ""
Write-Host "BytzGo Render setup" -ForegroundColor Cyan
Write-Host "==================="
Write-Host ""
Write-Host "1. Opening Render Blueprint in your browser..."
Write-Host "   $blueprintUrl"
Write-Host ""
Write-Host "2. Sign in to Render (GitHub) if asked."
Write-Host "3. Click Apply — creates Web Service 'byzgo' (Node API, not Static Site)."
Write-Host "4. Set secrets: DATABASE_URL, JWT_SECRET, GOOGLE_MAPS_API_KEY, Paystack, SMS."
Write-Host "5. After deploy is Live: Settings -> Custom Domains -> add bytzgo.net"
Write-Host "6. Remove bytzgo.net from any OLD Static Site service."
Write-Host ""

Start-Process $blueprintUrl

Write-Host "Waiting for https://bytzgo.net/api/health to return JSON (Ctrl+C to stop)..."
Write-Host ""

$script = Join-Path $repoRoot "scripts\verify-render-api.ps1"
while ($true) {
  & $script
  if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "Done. Rebuild APK: npm run flutter:build:apk" -ForegroundColor Green
    break
  }
  Start-Sleep -Seconds 20
}
