# Create upload keystore for Google Play. Use -NonInteractive for automated setup.
param([switch]$NonInteractive)

$ErrorActionPreference = "Stop"
$mobileRoot = Split-Path $PSScriptRoot -Parent
$androidDir = Join-Path $mobileRoot "android"
$keystore = Join-Path $androidDir "upload-keystore.jks"
$keyProps = Join-Path $androidDir "key.properties"
$example = Join-Path $androidDir "key.properties.example"
$backupNote = Join-Path $androidDir "PLAY_KEYSTORE_BACKUP.txt"

if (Test-Path $keystore) {
  Write-Host "Keystore already exists: $keystore" -ForegroundColor Yellow
  exit 0
}

$keytool = "keytool"
if (-not (Get-Command keytool -ErrorAction SilentlyContinue)) {
  $studioJbr = "${env:ProgramFiles}\Android\Android Studio\jbr\bin\keytool.exe"
  if (Test-Path $studioJbr) { $keytool = $studioJbr }
  else {
    Write-Host "keytool not found. Install Android Studio." -ForegroundColor Red
    exit 1
  }
}

$storePass = ""
$keyPass = ""
if ($NonInteractive) {
  $bytes = New-Object byte[] 24
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  $storePass = [Convert]::ToBase64String($bytes) -replace '[+/=]', 'x'
  $keyPass = $storePass
  Write-Host "Generated random keystore password (saved to key.properties and PLAY_KEYSTORE_BACKUP.txt)." -ForegroundColor Yellow
} else {
  Write-Host "You will be prompted for store and key passwords."
}

$dname = "CN=BytzGo, OU=Mobile, O=BytzGo, L=Accra, ST=Greater Accra, C=GH"
$args = @(
  "-genkey", "-v",
  "-keystore", $keystore,
  "-alias", "upload",
  "-keyalg", "RSA",
  "-keysize", "2048",
  "-validity", "10000",
  "-dname", $dname
)
if ($NonInteractive) {
  $args += @("-storepass", $storePass, "-keypass", $keyPass)
}

& $keytool @args
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$content = @"
storePassword=$storePass
keyPassword=$keyPass
keyAlias=upload
storeFile=upload-keystore.jks
"@
[System.IO.File]::WriteAllText($keyProps, $content.Trim())

if ($NonInteractive) {
  $note = @"
BytzGo Play upload keystore backup - KEEP SECRET
Created: $(Get-Date -Format o)
File: upload-keystore.jks
Alias: upload
Store password: $storePass
Key password: $keyPass

If you lose this file or password, you cannot update the app on Google Play.
"@
  [System.IO.File]::WriteAllText($backupNote, $note)
  Write-Host "Password backup: $backupNote" -ForegroundColor Yellow
} elseif (-not (Test-Path $keyProps)) {
  Copy-Item $example $keyProps
  Write-Host "Edit $keyProps with your passwords."
}

Write-Host "Keystore created: $keystore" -ForegroundColor Green
