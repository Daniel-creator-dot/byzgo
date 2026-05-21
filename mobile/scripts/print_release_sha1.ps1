# Print SHA-1 / SHA-256 for the Play Store upload keystore (Maps, Google Sign-In, Firebase).
param(
  [string]$Keystore = "",
  [string]$Alias = "upload"
)

$ErrorActionPreference = "Stop"
$mobileRoot = Split-Path $PSScriptRoot -Parent
$androidDir = Join-Path $mobileRoot "android"
if (-not $Keystore) {
  $Keystore = Join-Path $androidDir "upload-keystore.jks"
}

$keytool = "keytool"
$kt = Get-Command keytool -ErrorAction SilentlyContinue
if (-not $kt) {
  $studioJbr = "${env:ProgramFiles}\Android\Android Studio\jbr\bin\keytool.exe"
  if (Test-Path $studioJbr) { $keytool = $studioJbr }
}

if (-not (Test-Path $Keystore)) {
  Write-Host "Upload keystore not found: $Keystore" -ForegroundColor Red
  Write-Host "Run: .\scripts\create_upload_keystore.ps1"
  exit 1
}

$storePass = ""
$keyProps = Join-Path $androidDir "key.properties"
if (Test-Path $keyProps) {
  Get-Content $keyProps | ForEach-Object {
    if ($_ -match '^\s*storePassword\s*=\s*(.+)\s*$') {
      $storePass = $Matches[1].Trim()
    }
  }
}
if (-not $storePass) {
  Write-Host "No storePassword in android/key.properties" -ForegroundColor Red
  exit 1
}

$package = "com.example.bytzgo"
Write-Host "Package (applicationId): $package" -ForegroundColor Cyan
Write-Host "Keystore: $Keystore" -ForegroundColor Cyan
Write-Host ""

$out = & $keytool -list -v -keystore $Keystore -alias $Alias -storepass $storePass 2>&1
$out | Select-String -Pattern "SHA1:|SHA256:|Alias name:"

Write-Host ""
Write-Host "Add SHA-1 in:" -ForegroundColor Green
Write-Host "  Firebase Console - Project bytzgo-9bd89 - Android app - Add fingerprint"
Write-Host "  Google Cloud - Credentials - Android OAuth - package $package + SHA-1"
Write-Host "  Google Cloud - Maps API key - Android restriction - package $package + SHA-1"
