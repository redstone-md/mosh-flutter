$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/MossRecording.ps1"
function Assert-MossRecording($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$directory = Join-Path $env:RUNNER_TEMP ('mosh recording ' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory $directory)
$executable = Join-Path $directory 'Fake Mosh.exe'
Add-Type -OutputAssembly $executable -OutputType ConsoleApplication -TypeDefinition @'
using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
public static class RecordingFixture {
    public static void Main() {
        var home = AppDomain.CurrentDomain.BaseDirectory;
        var record = Environment.GetEnvironmentVariable("MOSH_DEBUG_RECORD_DIR");
        File.WriteAllText(Path.Combine(home, "observed-variable.txt"), record ?? "<unset>");
        File.WriteAllText(Path.Combine(home, "observed-directory.txt"), Environment.CurrentDirectory);
        if (!String.IsNullOrEmpty(record)) {
            Directory.CreateDirectory(record);
            var path = Path.Combine(record, "moss-debug-" + Process.GetCurrentProcess().Id + ".mossrec");
            File.WriteAllText(path, "{\"metric\":\"event\",\"data\":{\"kind\":\"node.start\"}}\n");
        }
        var delay = Path.Combine(home, "hold-ms.txt");
        Thread.Sleep(File.Exists(delay) ? Int32.Parse(File.ReadAllText(delay)) : 100);
    }
}
'@
$previous = $env:MOSH_DEBUG_RECORD_DIR
$children = @()
try {
    $env:MOSH_DEBUG_RECORD_DIR = 'parent-sentinel'
    $recordDirectory = Join-Path $directory 'private recording'
    $child = Start-MoshRecordingProcess $executable $recordDirectory
    $children += $child
    $record = Wait-MoshRecordingFile $child $recordDirectory 10
    Wait-MoshRecordingExit $child 10
    Assert-MossRecording ((Get-Content (Join-Path $directory 'observed-variable.txt') -Raw) -eq $recordDirectory) 'Child must receive its private recording directory'
    Assert-MossRecording ((Get-Content (Join-Path $directory 'observed-directory.txt') -Raw) -eq $directory) 'Working directory and executable paths with spaces must work'
    Assert-MossRecording ((Get-Content $record -Raw | ConvertFrom-Json).metric -eq 'event') 'Wait for a nonempty recorder file'

    Assert-MossRecording ($env:MOSH_DEBUG_RECORD_DIR -eq 'parent-sentinel') 'Parent environment must be unchanged'

    '15000' | Set-Content (Join-Path $directory 'hold-ms.txt')
    $held = Start-MoshRecordingProcess $executable $recordDirectory
    $children += $held
    $timedOut = $false
    try { Wait-MoshRecordingExit $held 1 } catch { $timedOut = $true }
    Assert-MossRecording ($timedOut -and -not $held.HasExited) 'Timeout must not kill the application'
    $missing = $false
    try { [void](Wait-MoshRecordingFile $held (Join-Path $directory 'missing') 1) } catch { $missing = $true }
    Assert-MossRecording ($missing) 'A missing recorder must fail within its deadline'
    Write-Host 'Moss recording launcher passed: isolated child environment, spaced paths and bounded waits.'
} finally {
    [Environment]::SetEnvironmentVariable('MOSH_DEBUG_RECORD_DIR', $previous, 'Process')
    foreach ($child in $children) {
        if (-not $child.HasExited) { $child.Kill(); $child.WaitForExit() }
    }
}
