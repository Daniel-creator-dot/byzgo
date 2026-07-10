# Safely set DATABASE_URL on production Render (validates before PUT).
param(
  [string]$ServiceId = 'srv-d98738e7r5hc73cjogv0',
  [string]$DatabaseUrl = $env:DATABASE_URL
)

$ErrorActionPreference = 'Stop'
if (-not $env:RENDER_API_KEY) {
  Write-Host 'Set RENDER_API_KEY first.' -ForegroundColor Yellow
  exit 1
}
if (-not $DatabaseUrl) {
  Write-Host 'Pass -DatabaseUrl or set DATABASE_URL in the environment.' -ForegroundColor Yellow
  exit 1
}
if ($DatabaseUrl -notmatch '^postgres(ql)?://.+@.+:\d+/') {
  Write-Host "Refusing invalid DATABASE_URL (length=$($DatabaseUrl.Length))." -ForegroundColor Red
  exit 1
}

$headers = @{
  Authorization = "Bearer $env:RENDER_API_KEY"
  Accept        = 'application/json'
  'Content-Type' = 'application/json'
}
$body = @{ value = $DatabaseUrl } | ConvertTo-Json
Invoke-RestMethod -Method Put -Uri "https://api.render.com/v1/services/$ServiceId/env-vars/DATABASE_URL" -Headers $headers -Body $body | Out-Null
Write-Host 'DATABASE_URL updated on Render.' -ForegroundColor Green
