# Bring Android Emulator to front and remind how to fit the window on screen.
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@

$proc = Get-Process qemu-system-x86_64 -ErrorAction SilentlyContinue | Select-Object -First 1
if ($proc -and $proc.MainWindowHandle -ne [IntPtr]::Zero) {
  [Win32]::ShowWindow($proc.MainWindowHandle, 9) | Out-Null
  [Win32]::SetForegroundWindow($proc.MainWindowHandle) | Out-Null
  Write-Host "Emulator focused: $($proc.MainWindowTitle)"
} else {
  Write-Host "Emulator process not found. Start it from Android Studio or:"
  Write-Host "  flutter emulators --launch Medium_Phone_API_36.1"
}

Write-Host ""
Write-Host "If the phone looks cut off or tiny:"
Write-Host "  1. Drag the emulator window corner to make it taller"
Write-Host "  2. In the emulator toolbar: ... > Window > Zoom to fit"
Write-Host "  3. Or press Ctrl+Down in the emulator window to zoom out"
Write-Host ""
Write-Host "Hot-reload login UI after code changes:"
Write-Host "  cd mobile"
Write-Host "  flutter run -d emulator-5554"

if (Test-Path $adb) {
  & $adb devices
}
