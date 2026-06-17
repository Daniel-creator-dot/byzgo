# One-time setup after cloning BytzGo — prepares Android Studio / Flutter on Windows.
# Run from repo root or mobile/:
#   powershell -ExecutionPolicy Bypass -File mobile\scripts\setup_android_studio.ps1
$ErrorActionPreference = "Stop"

$mobileRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $mobileRoot
Set-Location $mobileRoot

function Find-FlutterSdk {
    $cmd = Get-Command flutter -ErrorAction SilentlyContinue
    if ($cmd) {
        $bin = Split-Path -Parent $cmd.Source
        return (Resolve-Path (Join-Path $bin "..")).Path
    }
    $candidates = @(
        (Join-Path $repoRoot ".flutter-sdk"),
        "C:\src\flutter",
        "$env:LOCALAPPDATA\flutter",
        "$env:USERPROFILE\flutter",
        "$env:USERPROFILE\develop\flutter"
    )
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c "bin\flutter.bat")) {
            return (Resolve-Path $c).Path
        }
    }
    return $null
}

function Find-AndroidSdk {
    if ($env:ANDROID_HOME -and (Test-Path $env:ANDROID_HOME)) {
        return (Resolve-Path $env:ANDROID_HOME).Path
    }
    if ($env:ANDROID_SDK_ROOT -and (Test-Path $env:ANDROID_SDK_ROOT)) {
        return (Resolve-Path $env:ANDROID_SDK_ROOT).Path
    }
    $default = Join-Path $env:LOCALAPPDATA "Android\Sdk"
    if (Test-Path $default) { return (Resolve-Path $default).Path }
    return $null
}

function Escape-PropertiesPath([string]$path) {
    return ($path -replace '\\', '\\')
}

Write-Host ""
Write-Host "BytzGo — Android Studio setup" -ForegroundColor Cyan
Write-Host "=============================" -ForegroundColor Cyan
Write-Host ""

$flutterSdk = Find-FlutterSdk
if (-not $flutterSdk) {
    Write-Host "Flutter SDK not found." -ForegroundColor Red
    Write-Host "  1. Install: https://docs.flutter.dev/get-started/install/windows" -ForegroundColor Yellow
    Write-Host "  2. Add flutter\bin to PATH, or clone into $repoRoot\.flutter-sdk" -ForegroundColor Yellow
    Write-Host "  3. Re-run this script." -ForegroundColor Yellow
    exit 1
}

$androidSdk = Find-AndroidSdk
if (-not $androidSdk) {
    Write-Host "Android SDK not found." -ForegroundColor Red
    Write-Host "  Open Android Studio → SDK Manager → install Android SDK." -ForegroundColor Yellow
    Write-Host "  Default path: $env:LOCALAPPDATA\Android\Sdk" -ForegroundColor Yellow
    exit 1
}

Write-Host "Flutter SDK : $flutterSdk" -ForegroundColor Green
Write-Host "Android SDK : $androidSdk" -ForegroundColor Green
Write-Host ""

# local.properties (required for Gradle — gitignored, machine-specific)
$localProps = Join-Path $mobileRoot "android\local.properties"
$mapsKey = ""
$envLocal = Join-Path $repoRoot ".env.local"
if (Test-Path $envLocal) {
    Get-Content $envLocal | ForEach-Object {
        if ($_ -match '^\s*(?:GOOGLE_MAPS_API_KEY|VITE_GOOGLE_MAPS_API_KEY)\s*=\s*(.+)\s*$') {
            $mapsKey = $Matches[1].Trim().Trim('"').Trim("'")
        }
    }
}

$lines = @(
    "flutter.sdk=$(Escape-PropertiesPath $flutterSdk)",
    "sdk.dir=$(Escape-PropertiesPath $androidSdk)"
)
if ($mapsKey) {
    $lines += "GOOGLE_MAPS_API_KEY=$mapsKey"
}
Set-Content -Path $localProps -Value ($lines -join "`n") -Encoding UTF8
Write-Host "Wrote android\local.properties" -ForegroundColor Green

# dart_defines.json (gitignored — API URL + OAuth client for flutter run)
$dartDefines = Join-Path $mobileRoot "dart_defines.json"
if (-not (Test-Path $dartDefines)) {
    Copy-Item (Join-Path $mobileRoot "dart_defines.json.example") $dartDefines
    Write-Host "Created dart_defines.json from example" -ForegroundColor Green
} else {
    Write-Host "dart_defines.json already exists — kept" -ForegroundColor Gray
}

if (Test-Path (Join-Path $PSScriptRoot "sync_maps_key.ps1")) {
    Write-Host ""
    Write-Host "Syncing Maps key (optional)..." -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot "sync_maps_key.ps1")
}

Write-Host ""
Write-Host "Running flutter pub get..." -ForegroundColor Cyan
& (Join-Path $flutterSdk "bin\flutter.bat") pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Running flutter doctor..." -ForegroundColor Cyan
& (Join-Path $flutterSdk "bin\flutter.bat") doctor

Write-Host ""
Write-Host "Setup complete." -ForegroundColor Green
Write-Host ""
Write-Host "Android Studio:" -ForegroundColor Cyan
Write-Host "  1. File → Open → select folder: $mobileRoot"
Write-Host "  2. Install Flutter + Dart plugins (Settings → Plugins) if prompted"
Write-Host "  3. View → Tool Windows → Device Manager → Play on a virtual device"
Write-Host "  4. Open lib\main.dart → click Run, or use run config 'BytzGo (production)'"
Write-Host ""
Write-Host "Terminal (live API):" -ForegroundColor Cyan
Write-Host "  cd $repoRoot"
Write-Host "  npm run flutter:android"
Write-Host ""
Write-Host "Terminal (local backend on port 3000):" -ForegroundColor Cyan
Write-Host "  npm run backend          # terminal 1"
Write-Host "  npm run flutter:android:local   # terminal 2"
Write-Host ""
