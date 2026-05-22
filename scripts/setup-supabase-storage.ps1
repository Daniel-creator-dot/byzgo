# Configure Supabase Storage for BytzGo (local backend/.env + Render).
# Usage:
#   $env:SUPABASE_SERVICE_ROLE_KEY = '<service_role from Supabase Dashboard → Settings → API>'
#   .\scripts\setup-supabase-storage.ps1
# Or:
#   .\scripts\setup-supabase-storage.ps1 -ServiceRoleKey '<key>'
param(
  [string]$ServiceRoleKey = $env:SUPABASE_SERVICE_ROLE_KEY,
  [string]$ProductionServiceId = 'srv-d7use31o3t8c73fu3eig',  # byzgoback (www.bytzgo.net)
  [string[]]$RenderServiceIds = @(
    'srv-d7use31o3t8c73fu3eig',  # byzgoback - production API + custom domains
    'srv-d86e8qv7f7vs7395kgrg'   # byzgo-api - staging / direct onrender URL
  )
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$backendEnv = Join-Path $repoRoot 'backend\.env'
$supabaseUrl = 'https://ypmiurbtmfiyzmrygonh.supabase.co'
$bucket = 'pictures'

function Set-EnvLine([string]$path, [string]$key, [string]$value) {
  $lines = @()
  if (Test-Path $path) { $lines = Get-Content $path }
  $found = $false
  $out = foreach ($line in $lines) {
    if ($line -match "^$([regex]::Escape($key))=") {
      $found = $true
      "$key=$value"
    } else { $line }
  }
  if (-not $found) { $out += "$key=$value" }
  Set-Content -Path $path -Value ($out -join "`n") -Encoding UTF8
}

function Get-RenderAnonKey() {
  if (-not $env:RENDER_API_KEY) { return $null }
  $headers = @{ Authorization = "Bearer $env:RENDER_API_KEY"; Accept = 'application/json' }
  foreach ($sid in $RenderServiceIds) {
    try {
      $vars = Invoke-RestMethod -Uri "https://api.render.com/v1/services/$sid/env-vars?limit=100" -Headers $headers
      foreach ($item in $vars) {
        if ($item.envVar.key -eq 'SUPABASE_ANON_KEY' -and $item.envVar.value) {
          return $item.envVar.value
        }
      }
    } catch { }
  }
  return $null
}

function Set-RenderEnvVar([string]$serviceId, [string]$key, [string]$value) {
  if (-not $env:RENDER_API_KEY) {
    Write-Warning "RENDER_API_KEY not set - skip Render update for $key"
    return
  }
  $headers = @{
    Authorization = "Bearer $env:RENDER_API_KEY"
    Accept        = 'application/json'
    'Content-Type' = 'application/json'
  }
  $body = @{ value = $value } | ConvertTo-Json
  Invoke-RestMethod -Method Put -Uri "https://api.render.com/v1/services/$serviceId/env-vars/$key" -Headers $headers -Body $body | Out-Null
  Write-Host "Render $serviceId : set $key" -ForegroundColor Green
}

Write-Host 'Applying Supabase storage SQL (optional if pooler lacks owner)...' -ForegroundColor Cyan
Push-Location (Join-Path $repoRoot 'backend')
$sqlOk = $true
try {
  node scripts/run-supabase-storage-sql.mjs
  if ($LASTEXITCODE -ne 0) { $sqlOk = $false }
} catch { $sqlOk = $false }
Pop-Location
if (-not $sqlOk) {
  Write-Host 'SQL via DATABASE_URL failed or skipped - paste backend/supabase-storage.sql into Supabase SQL Editor.' -ForegroundColor Yellow
}

Set-EnvLine $backendEnv 'SUPABASE_URL' $supabaseUrl
Set-EnvLine $backendEnv 'SUPABASE_STORAGE_BUCKET' $bucket

$anon = Get-RenderAnonKey
if ($anon) {
  Set-EnvLine $backendEnv 'SUPABASE_ANON_KEY' $anon
  Write-Host 'backend/.env: SUPABASE_ANON_KEY synced from Render' -ForegroundColor Green
}

if ([string]::IsNullOrWhiteSpace($ServiceRoleKey)) {
  Write-Host ''
  Write-Host 'SUPABASE_SERVICE_ROLE_KEY is required.' -ForegroundColor Yellow
  Write-Host '1. Open https://supabase.com/dashboard/project/ypmiurbtmfiyzmrygonh/settings/api'
  Write-Host '2. Copy the service_role secret key'
  Write-Host '3. Run:'
  Write-Host '   $env:SUPABASE_SERVICE_ROLE_KEY = ''<paste key>'''
  Write-Host '   .\scripts\setup-supabase-storage.ps1'
  exit 1
}

Set-EnvLine $backendEnv 'SUPABASE_SERVICE_ROLE_KEY' $ServiceRoleKey.Trim()
Write-Host 'backend/.env: SUPABASE_SERVICE_ROLE_KEY set' -ForegroundColor Green

foreach ($sid in $RenderServiceIds) {
  Set-RenderEnvVar $sid 'SUPABASE_URL' $supabaseUrl
  Set-RenderEnvVar $sid 'SUPABASE_STORAGE_BUCKET' $bucket
  if ($anon) { Set-RenderEnvVar $sid 'SUPABASE_ANON_KEY' $anon }
  Set-RenderEnvVar $sid 'SUPABASE_SERVICE_ROLE_KEY' $ServiceRoleKey.Trim()
}

Write-Host 'Verifying storage...' -ForegroundColor Cyan
Push-Location (Join-Path $repoRoot 'backend')
node scripts/verify-storage.mjs
$code = $LASTEXITCODE
Pop-Location

& (Join-Path $repoRoot 'scripts\prepare-render-env.ps1')

if ($code -ne 0) { exit $code }

if ($env:RENDER_API_KEY) {
  Write-Host 'Redeploying production (byzgoback) so new env vars load...' -ForegroundColor Cyan
  & (Join-Path $repoRoot 'scripts\redeploy-production.ps1') -ServiceId $ProductionServiceId
}

Write-Host ''
Write-Host 'Done. Production API: https://www.bytzgo.net (byzgoback).' -ForegroundColor Green
Write-Host 'Verify: .\scripts\verify-render-api.ps1 -Url https://www.bytzgo.net' -ForegroundColor Cyan
