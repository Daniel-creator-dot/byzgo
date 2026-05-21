# Pre-upload checks for Google Play. Exit 1 if any hard failure.
$ErrorActionPreference = "Stop"
$mobileRoot = Split-Path $PSScriptRoot -Parent
$repoRoot = Resolve-Path (Join-Path $mobileRoot "..")
$fail = 0

function Fail([string]$msg) {
  Write-Host "FAIL: $msg" -ForegroundColor Red
  $script:fail++
}
function Ok([string]$msg) {
  Write-Host "OK: $msg" -ForegroundColor Green
}

$gradle = Join-Path $mobileRoot "android\app\build.gradle.kts"
$gs = Join-Path $mobileRoot "android\app\google-services.json"
$keyProps = Join-Path $mobileRoot "android\key.properties"
$aab = Join-Path $mobileRoot "build\app\outputs\bundle\release\app-release.aab"

if (Test-Path $gradle) {
  $g = Get-Content $gradle -Raw
  if ($g -match 'applicationId\s*=\s*"com\.example\.') {
    Fail "applicationId still uses com.example (Play will reject)"
  } elseif ($g -match 'applicationId\s*=\s*"net\.bytzgo\.app"') {
    Ok "applicationId is net.bytzgo.app"
  } else {
    Fail "applicationId not set to net.bytzgo.app"
  }
  if ($g -match 'targetSdk\s*=\s*35') {
    Ok "targetSdk 35"
  } else {
    Fail "targetSdk should be 35 for current Play requirements"
  }
}

if (Test-Path $gs) {
  $j = Get-Content $gs -Raw
  if ($j -match '"package_name":\s*"com\.example\.bytzgo"') {
    Fail "google-services.json still has com.example.bytzgo - add net.bytzgo.app in Firebase and replace file"
  } elseif ($j -match '"package_name":\s*"net\.bytzgo\.app"') {
    Ok "google-services.json package net.bytzgo.app"
  }
}

if (-not (Test-Path $keyProps)) {
  Fail "android/key.properties missing (unsigned release)"
} else {
  Ok "key.properties present"
}

$manifest = Join-Path $mobileRoot "android\app\src\main\AndroidManifest.xml"
if (Test-Path $manifest) {
  $m = Get-Content $manifest -Raw
  if ($m -match 'READ_MEDIA_IMAGES|READ_EXTERNAL_STORAGE') {
    Fail "Manifest still declares broad storage (Play photo policy risk)"
  } else {
    Ok "No broad storage permissions in manifest"
  }
}

foreach ($url in @("https://www.bytzgo.net/privacy", "https://www.bytzgo.net/account-deletion")) {
  try {
    $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 20
    if ($r.StatusCode -eq 200) { Ok "$url" } else { Fail "$url returned $($r.StatusCode)" }
  } catch {
    Fail "$url not reachable"
  }
}

if (Test-Path $aab) {
  $aabTime = (Get-Item $aab).LastWriteTime
  $gradleTime = (Get-Item $gradle).LastWriteTime
  if ($aabTime -lt $gradleTime) {
    Write-Host "WARN: AAB is older than build.gradle.kts - rebuild: npm run flutter:build:aab" -ForegroundColor Yellow
  } else {
    Ok "AAB exists: $aab"
  }
} else {
  Write-Host "WARN: AAB not built yet - run npm run flutter:build:aab" -ForegroundColor Yellow
}

Write-Host ""
if ($fail -gt 0) {
  Write-Host "$fail check(s) failed. See docs/PLAY_STORE_REJECTION_AUDIT.md" -ForegroundColor Red
  exit 1
}
Write-Host "All Play release checks passed." -ForegroundColor Green
