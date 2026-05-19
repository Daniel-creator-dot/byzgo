# Quick check that production serves JSON from Node, not the static SPA.
# Usage: .\scripts\verify-render-api.ps1
#        .\scripts\verify-render-api.ps1 -Url "https://bytzgo.net"

param(
  [string]$Url = "https://bytzgo.net"
)

$ErrorActionPreference = "Stop"
$health = "$($Url.TrimEnd('/'))/api/health"

Write-Host "GET $health"
try {
  $res = Invoke-WebRequest -Uri $health -UseBasicParsing -TimeoutSec 30
} catch {
  Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}

$contentType = $res.Headers["Content-Type"]
$body = $res.Content.Trim()

Write-Host "Status: $($res.StatusCode)"
Write-Host "Content-Type: $contentType"
Write-Host "Body (first 200 chars): $($body.Substring(0, [Math]::Min(200, $body.Length)))"

if ($contentType -notmatch "application/json" -and $body -notmatch '^\s*\{') {
  Write-Host ""
  Write-Host "FAIL: Response is HTML (static site), not the Node API." -ForegroundColor Red
  Write-Host "Fix: Render Dashboard -> change bytzgo to Web Service (see docs/RENDER.md)" -ForegroundColor Yellow
  exit 1
}

if ($body -notmatch '"ok"\s*:\s*true') {
  Write-Host "FAIL: JSON does not look like /api/health" -ForegroundColor Red
  exit 1
}

Write-Host ""
Write-Host "OK: API is live. APK can use API_URL=$Url" -ForegroundColor Green
