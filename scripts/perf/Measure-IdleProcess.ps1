param([int]$TargetProcessId, [int]$Seconds = 120, [string]$OutputFile)
$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ProfileThreadName {
 [DllImport("kernel32.dll")] static extern IntPtr OpenThread(uint access, bool inherit, uint id);
 [DllImport("kernel32.dll")] static extern int GetThreadDescription(IntPtr thread, out IntPtr text);
 [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr memory);
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
 public static string Read(uint id) {
  IntPtr handle = OpenThread(0x800, false, id), text = IntPtr.Zero;
  if (handle == IntPtr.Zero) return "";
  try { return GetThreadDescription(handle, out text) == 0 ? Marshal.PtrToStringUni(text) : ""; }
  finally { if (text != IntPtr.Zero) LocalFree(text); CloseHandle(handle); }
 }
}
'@

function Get-Threads($Process) {
    $modules = @($Process.Modules | ForEach-Object {
        @{ name = $_.ModuleName; start = $_.BaseAddress.ToInt64(); end = $_.BaseAddress.ToInt64() + $_.ModuleMemorySize }
    })
    $rows = @{}
    foreach ($thread in $Process.Threads) {
        try {
            $address = $thread.StartAddress.ToInt64()
            $module = @($modules | Where-Object { $address -ge $_.start -and $address -lt $_.end })
            $rows[$thread.Id] = @{
                tid = $thread.Id; name = [ProfileThreadName]::Read($thread.Id)
                start_module = if ($module.Count) { $module[0].name } else { 'unknown' }
                cpu_ms = $thread.TotalProcessorTime.TotalMilliseconds
            }
        } catch { }
    }
    return $rows
}

$process = Get-Process -Id $TargetProcessId
$before = Get-Threads $process
if ($before.Count -eq 0) { throw 'No readable target threads' }
$last = $before.Clone()
$cpuBefore = $process.TotalProcessorTime.TotalMilliseconds
$timer = [Diagnostics.Stopwatch]::StartNew()
$samples = [Collections.Generic.List[object]]::new()
while ($timer.Elapsed.TotalSeconds -lt $Seconds) {
    Start-Sleep -Milliseconds 1000
    $process.Refresh()
    if ($process.HasExited) { throw 'Profile target exited during measurement' }
    $samples.Add(@{ second = $timer.Elapsed.TotalSeconds; cpu_ms = $process.TotalProcessorTime.TotalMilliseconds; rss = $process.WorkingSet64 })
    $current = Get-Threads $process
    foreach ($key in $current.Keys) { $last[$key] = $current[$key] }
}
$elapsed = $timer.Elapsed.TotalSeconds
$cpu = $process.TotalProcessorTime.TotalMilliseconds - $cpuBefore
$threads = @($last.Keys | ForEach-Object {
    $row = $last[$_].Clone()
    $row.cpu_ms -= $(if ($before.ContainsKey($_)) { $before[$_].cpu_ms } else { 0 })
    $row
} | Sort-Object { $_.cpu_ms } -Descending)
$result = @{
    pid = $TargetProcessId; elapsed_seconds = $elapsed; cpu_one_core_percent = 100 * $cpu / ($elapsed * 1000)
    cpu_ms = $cpu; threads = $threads; samples = @($samples.ToArray())
    thread_note = 'Thread CPU deltas and start modules are attribution hints, not sampled call stacks.'
}
$result | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $OutputFile
Write-Output ('MEASURED cpu={0:N2}% seconds={1:N2}' -f $result.cpu_one_core_percent, $elapsed)
