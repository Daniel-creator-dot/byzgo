# Set SUPABASE_SERVICE_ROLE_KEY on local backend + all BytzGo Render services, then verify.
# Usage (paste key from Supabase Dashboard → Settings → API → service_role):
#   $env:SUPABASE_SERVICE_ROLE_KEY = 'eyJ...'
#   .\scripts\apply-supabase-key.ps1

param(
  [string]$ServiceRoleKey = $env:SUPABASE_SERVICE_ROLE_KEY
)

if ([string]::IsNullOrWhiteSpace($ServiceRoleKey)) {
  Write-Host 'Missing SUPABASE_SERVICE_ROLE_KEY.' -ForegroundColor Yellow
  Write-Host '1. Open https://supabase.com/dashboard/project/ypmiurbtmfiyzmrygonh/settings/api'
  Write-Host '2. Under Project API keys, copy service_role (secret)'
  Write-Host '3. Run:'
  Write-Host "   `$env:SUPABASE_SERVICE_ROLE_KEY = '<paste>'"
  Write-Host '   .\scripts\apply-supabase-key.ps1'
  exit 1
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
& (Join-Path $repoRoot 'scripts\setup-supabase-storage.ps1') -ServiceRoleKey $ServiceRoleKey.Trim()
