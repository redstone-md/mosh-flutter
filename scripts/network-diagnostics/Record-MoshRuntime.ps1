param([ValidateRange(30, 600)][int]$DurationSeconds = 180)
$ErrorActionPreference = 'Stop'
$recorded = $null
$recording = $null
trap {
    Write-Host "Recording failed: $($_.Exception.Message)"
    if ($recording -and (Test-Path $recording)) {
        Write-Host "Your recording is preserved: $recording"
        Write-Host 'Send this .mossrec file in the private diagnostic conversation; no repeat capture is needed.'
    }
    if ($null -ne $recorded -and -not $recorded.HasExited) {
        Write-Host 'To end diagnostic mode, quit Mosh from its tray icon and open it normally.'
    }
    exit 1
}
. "$PSScriptRoot/MossRecording.ps1"

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run Start-MossRecording.cmd normally, without administrator rights, to keep Mosh unelevated.'
}
$candidates = @(Get-Process -Name mosh -ErrorAction SilentlyContinue)
if ($candidates.Count -ne 1) { throw 'Open one Mosh instance before starting this tool.' }
$original = $candidates[0]
$executable = $original.Path
if (-not $executable) { throw 'The running Mosh executable path is unavailable.' }
$version = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($executable).ProductVersion
$stamp = [datetime]::UtcNow.ToString('yyyyMMdd-HHmmss')
$directory = Join-Path $env:LOCALAPPDATA ('Mosh/Diagnostics/moss-{0}-{1}' -f $stamp, [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory $directory)

Write-Host '1. Quit Mosh using its tray icon > Quit. This tool will reopen it in recording mode.'
Write-Host 'The tool never kills Mosh and does not change its stored settings.'
Wait-MoshRecordingExit $original
$recorded = Start-MoshRecordingProcess $executable $directory
$processStartedAt = $recorded.StartTime.ToUniversalTime()
Write-Host '2. Unlock Mosh if asked and open a saved chat. Waiting for its network recorder...'
$recording = Wait-MoshRecordingFile $recorded $directory
$startedAt = [datetime]::UtcNow
$watch = [System.Diagnostics.Stopwatch]::StartNew()
Write-Host "3. Leave Mosh idle for $DurationSeconds seconds. Avoid calls and file transfers."
while (-not $recorded.HasExited -and $watch.Elapsed.TotalSeconds -lt $DurationSeconds) {
    $remaining = [math]::Max(0, [math]::Ceiling($DurationSeconds - $watch.Elapsed.TotalSeconds))
    Write-Progress -Activity 'Recording Moss runtime' -Status "$remaining seconds remaining" `
        -PercentComplete ([math]::Min(100, $watch.Elapsed.TotalSeconds / $DurationSeconds * 100))
    Start-Sleep -Seconds 1
}
Write-Progress -Activity 'Recording Moss runtime' -Completed
$intervalEndedAt = [datetime]::UtcNow
if (-not $recorded.HasExited) {
    Write-Host '4. Recording interval complete. Quit Mosh from its tray icon once more.'
    Write-Host 'Keep this tool window open until Mosh has exited.'
    Wait-MoshRecordingExit $recorded
}
$summary = @{
    format_version = 1; process_id = $recorded.Id; app_version = $version
    process_start_utc = $processStartedAt.ToString('o')
    started_utc = $startedAt.ToString('o')
    requested_interval_ended_utc = $intervalEndedAt.ToString('o')
    requested_seconds = $DurationSeconds
    source = 'Existing MOSH_DEBUG_RECORD_DIR recorder; events and five-second runtime snapshots'
}
$archive = Save-MoshRecordingReport $recording $summary $watch
Write-Host "Report ready: $archive"
Write-Host 'This ZIP contains private network metadata. Send it only in the private diagnostic conversation.'
Write-Host 'Open Mosh normally using its usual shortcut. No persistent environment settings were changed.'
Write-Host 'No private keys, databases or ETL files were copied.'
