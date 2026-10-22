param([int]$TargetProcessId, [string]$OutputFile, [switch]$Hide)
$ErrorActionPreference = 'Stop'
Add-Type -Path (Join-Path $PSScriptRoot 'ProfileAccessibility.cs') -ReferencedAssemblies Accessibility
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ProfileWindow {
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int command);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
 [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hwnd, int x, int y, int w, int h, bool repaint);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
 [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint x, uint y, uint data, UIntPtr extra);
}
'@
$process = Get-Process -Id $TargetProcessId
$deadline = [DateTime]::UtcNow.AddSeconds(60)
while ($process.MainWindowHandle -eq [IntPtr]::Zero) {
    if ([DateTime]::UtcNow -gt $deadline) { throw 'No Mosh GUI window' }
    Start-Sleep -Milliseconds 500
    $process.Refresh()
}
$hwnd = $process.MainWindowHandle
if ($Hide) { [ProfileWindow]::ShowWindow($hwnd, 6) | Out-Null; exit 0 }
[ProfileWindow]::ShowWindow($hwnd, 9) | Out-Null
[ProfileWindow]::MoveWindow($hwnd, 0, 0, 1280, 900, $true) | Out-Null
[ProfileWindow]::SetForegroundWindow($hwnd) | Out-Null
while ([DateTime]::UtcNow -lt $deadline) {
    $elements = [ProfileAccessibility]::Read($hwnd)
    $rows = @($elements | ForEach-Object { $_.Name -replace 'mosh://\S+', '<fixture-uri>' })
    $rows | ConvertTo-Json | Set-Content -Encoding UTF8 $OutputFile
    $candidate = @($elements | Where-Object { $_.Name -like '*Offline 7*' -and $_.Width -gt 0 })
    if ($candidate.Count) {
        $bounds = $candidate[0]
        [ProfileWindow]::SetCursorPos([int]($bounds.X + $bounds.Width / 2), [int]($bounds.Y + $bounds.Height / 2)) | Out-Null
        [ProfileWindow]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
        [ProfileWindow]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Seconds 2
        $after = [ProfileAccessibility]::Read($hwnd)
        $names = @($after | ForEach-Object { $_.Name -replace 'mosh://\S+', '<fixture-uri>' })
        $names | ConvertTo-Json | Set-Content -Encoding UTF8 $OutputFile
        if (@($names | Where-Object { $_ -like '*Write a message*' }).Count) { Write-Output 'Offline DM and composer visible'; exit 0 }
    }
    Start-Sleep -Seconds 1
}
throw 'Could not verify the saved offline DM/composer through MSAA'
