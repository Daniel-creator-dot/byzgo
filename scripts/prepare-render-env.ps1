# Merge backend/.env + .env.local into backend/.env.render for Render "Add from .env"
$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$backendEnv = Join-Path $repoRoot "backend\.env"
$localEnv = Join-Path $repoRoot ".env.local"
$out = Join-Path $repoRoot "backend\.env.render"

function Read-EnvFile([string]$path) {
  $map = @{}
  if (-not (Test-Path $path)) { return $map }
  foreach ($line in Get-Content $path) {
    $t = $line.Trim()
    if (-not $t -or $t.StartsWith("#")) { continue }
    if ($t -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
      $map[$Matches[1]] = $Matches[2]
    }
  }
  return $map
}

$merged = @{}
foreach ($k in (Read-EnvFile $backendEnv).Keys) { $merged[$k] = (Read-EnvFile $backendEnv)[$k] }
foreach ($k in (Read-EnvFile $localEnv).Keys) { $merged[$k] = (Read-EnvFile $localEnv)[$k] }

# Render production overrides
$merged["NODE_ENV"] = "production"
$merged["SERVE_WEB"] = "false"
$merged["APP_URL"] = "https://bytzgo.net"
$merged["PAYSTACK_CALLBACK_URL"] = "https://bytzgo.net"
if (-not $merged["FIREBASE_PROJECT_ID"]) { $merged["FIREBASE_PROJECT_ID"] = "bytzgo-72f1c" }
if ($merged["GOOGLE_MAPS_API_KEY"] -and -not $merged["VITE_GOOGLE_MAPS_API_KEY"]) {
  $merged["VITE_GOOGLE_MAPS_API_KEY"] = $merged["GOOGLE_MAPS_API_KEY"]
}

$lines = @(
  "# Generated for Render - upload via Environment Add from .env",
  "# File: backend\.env.render (gitignored)",
  ""
)
foreach ($key in ($merged.Keys | Sort-Object)) {
  # Render sets PORT automatically — do not override
  if ($key -match '^(GEMINI_|GEMINI_API|VITE_SUPABASE|VITE_API|MOBILE_|PORT)$') { continue }
  $lines += "$key=$($merged[$key])"
}

Set-Content -Path $out -Value ($lines -join "`n") -Encoding UTF8
Write-Host "Created: $out" -ForegroundColor Green
Write-Host ""
Write-Host "In Render -> Environment -> Add from .env -> select that file." -ForegroundColor Cyan
Write-Host "Missing in your local env (add in Render if you use them):" -ForegroundColor Yellow
if (-not $merged["PAYSTACK_PUBLIC_KEY"]) { Write-Host "  - PAYSTACK_PUBLIC_KEY" }
if (-not $merged["PAYSTACK_SECRET_KEY"]) { Write-Host "  - PAYSTACK_SECRET_KEY" }
if (-not $merged["SMS_API_KEY"]) { Write-Host "  - SMS_API_KEY (optional - OTP SMS)" }
