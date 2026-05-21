# Print Android package + SHA-1 for Google Sign-In (fixes PlatformException code 10).
# Add these in Google Cloud / Firebase for project bytzgo-72f1c.

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
Write-Host "Google Cloud Console:" -ForegroundColor Green
Write-Host "  https://console.cloud.google.com/apis/credentials?project=bytzgo-72f1c"
Write-Host ""
Write-Host "1. Create credentials -> OAuth client ID -> Android"
Write-Host "2. Package: $package"
Write-Host "3. Paste SHA-1 from above"
Write-Host "4. Keep existing Web client for serverClientId (GOOGLE_WEB_CLIENT_ID)"
Write-Host ""
Write-Host "Wait 5-10 minutes, then reinstall the APK and try Continue with Google."
