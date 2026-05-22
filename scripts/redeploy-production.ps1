# Redeploy the production API (byzgoback — hosts www.bytzgo.net / bytzgo.net).
# Requires RENDER_API_KEY in the environment.
param(
  [string]$ServiceId = 'srv-d7use31o3t8c73fu3eig'
)

$ErrorActionPreference = 'Stop'
if (-not $env:RENDER_API_KEY) {
  Write-Host 'Set RENDER_API_KEY first (Render Dashboard → Account Settings → API Keys).' -ForegroundColor Yellow
  exit 1
}

$headers = @{
  Authorization = "Bearer $env:RENDER_API_KEY"
  Accept        = 'application/json'
}

Write-Host "Triggering deploy for $ServiceId (byzgoback)..." -ForegroundColor Cyan
$r = Invoke-WebRequest -Method Post -Uri "https://api.render.com/v1/services/$ServiceId/deploys" -Headers $headers -UseBasicParsing
$deploy = $r.Content | ConvertFrom-Json
Write-Host "Deploy $($deploy.id) status=$($deploy.status)" -ForegroundColor Green
Write-Host 'Wait ~2 min, then: .\scripts\verify-render-api.ps1 -Url https://www.bytzgo.net' -ForegroundColor Cyan
