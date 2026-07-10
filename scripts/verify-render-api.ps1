# Quick check that production serves JSON from Node with Supabase storage.
# Usage: .\scripts\verify-render-api.ps1
#        .\scripts\verify-render-api.ps1 -Url "https://www.bytzgo.net"

param(
  [string]$Url = "https://www.bytzgo.net"
)

$ErrorActionPreference = "Stop"
$health = "$($Url.TrimEnd('/'))/api/health?deep=1"

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
Write-Host "Body (first 300 chars): $($body.Substring(0, [Math]::Min(300, $body.Length)))"

if ($contentType -notmatch "application/json" -and $body -notmatch '^\s*\{') {
  Write-Host ""
  Write-Host "FAIL: Response is HTML (static site), not the Node API." -ForegroundColor Red
  Write-Host "Fix: Point bytzgo.net to Web Service byzgoback (see docs/RENDER.md)" -ForegroundColor Yellow
  exit 1
}

if ($body -notmatch '"ok"\s*:\s*true') {
  Write-Host "FAIL: JSON does not look like /api/health" -ForegroundColor Red
  exit 1
}

$json = $body | ConvertFrom-Json
$storage = $json.media.storage
$storageOk = $json.media.storageOk
$base = $json.media.publicBaseUrl

Write-Host ""
if ($storage -eq 'supabase' -and $storageOk) {
  Write-Host "OK: API + Supabase storage live. publicBaseUrl=$base" -ForegroundColor Green
  Write-Host "APK can use API_URL=$Url"
  exit 0
}

Write-Host "WARN: API is up but storage is not healthy." -ForegroundColor Yellow
Write-Host "  media.storage=$storage storageOk=$storageOk"
Write-Host "  Run: .\scripts\setup-supabase-storage.ps1 then .\scripts\redeploy-production.ps1"
exit 1
