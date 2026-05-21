# Start BytzGo admin web dashboard on your laptop (API + Vite).
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

$backendJob = Start-Job -ScriptBlock {
    Set-Location $using:repoRoot
    npm run backend 2>&1
}

Write-Host "Backend starting (job $($backendJob.Id))..."
Start-Sleep -Seconds 4

$env:JAVA_HOME = $env:JAVA_HOME
if (-not $env:JAVA_HOME) {
    $jbr = "C:\Program Files\Android\Android Studio\jbr"
    if (Test-Path "$jbr\bin\java.exe") { $env:JAVA_HOME = $jbr }
}

Write-Host ""
Write-Host "Admin dashboard: http://localhost:5173/admin"
Write-Host "Login: admin@bytzgo.net / Admin@2026  (or npm run create:admin)"
Write-Host "Press Ctrl+C to stop the web UI; backend job may keep running — stop with: Stop-Job $($backendJob.Id); Remove-Job $($backendJob.Id)"
Write-Host ""

npm run dev:admin
