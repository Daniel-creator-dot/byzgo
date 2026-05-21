# Print Android package + SHA-1 for Google Sign-In (fixes PlatformException code 10).
# Add debug SHA-1 in Firebase for project bytzgo-9bd89 (matches google-services.json).

$ErrorActionPreference = "Stop"
$package = "net.bytzgo.app"
$keystore = Join-Path $env:USERPROFILE ".android\debug.keystore"

$keytool = @(
  "$env:JAVA_HOME\bin\keytool.exe",
  "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $keytool) {
  Write-Host "keytool not found. Install Android Studio or set JAVA_HOME." -ForegroundColor Red
  exit 1
}
if (-not (Test-Path $keystore)) {
  Write-Host "Debug keystore not found: $keystore" -ForegroundColor Red
  exit 1
}

Write-Host ""
Write-Host "BytzGo Google Sign-In (Android)" -ForegroundColor Cyan
Write-Host "================================"
Write-Host "Package name: $package"
Write-Host ""
Write-Host "SHA-1 fingerprints (debug keystore, used by current release APK):" -ForegroundColor Yellow
& $keytool -list -v -keystore $keystore -alias androiddebugkey -storepass android -keypass android |
  Select-String "SHA1:|SHA256:"

Write-Host ""
Write-Host "Firebase (recommended):" -ForegroundColor Green
Write-Host "  https://console.firebase.google.com/project/bytzgo-9bd89/settings/general"
Write-Host "  -> Your apps -> Android net.bytzgo.app -> Add fingerprint -> paste SHA-1 above"
Write-Host ""
Write-Host "serverClientId must be the Web client from google-services.json (type 3):"
Write-Host "  645977332644-4gjjf08268b3irafs4bh8b7guct1i1jb.apps.googleusercontent.com"
Write-Host ""
Write-Host "Wait 5-10 minutes, then reinstall the APK and try Continue with Google."
