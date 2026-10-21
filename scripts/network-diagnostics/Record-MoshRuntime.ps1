param([ValidateRange(30, 600)][int]$DurationSeconds = 180)
$ErrorActionPreference = 'Stop'
$recorded = $null
trap {
    Write-Host "Recording failed: $($_.Exception.Message)"
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
$stoppedAt = [datetime]::UtcNow
if (-not $recorded.HasExited) {
    Write-Host '4. Recording interval complete. Quit Mosh from its tray icon once more.'
    Write-Host 'Keep this tool window open until Mosh has exited.'
    Wait-MoshRecordingExit $recorded
}
$metadata = Join-Path $directory 'moss-runtime-summary.json'
@{
    format_version = 1; process_id = $recorded.Id; app_version = $version
    started_utc = $startedAt.ToString('o'); stopped_utc = $stoppedAt.ToString('o')
    observed_seconds = ($stoppedAt - $startedAt).TotalSeconds; requested_seconds = $DurationSeconds
    record_limit_bytes = 64MB; at_size_limit = ((Get-Item $recording).Length -ge 64MB)
    source = 'Existing MOSH_DEBUG_RECORD_DIR recorder; events and five-second runtime snapshots'
} | ConvertTo-Json | Set-Content $metadata -Encoding UTF8
$archive = Join-Path $directory 'mosh-runtime-report.zip'
Compress-Archive -Path @($recording, $metadata) -DestinationPath $archive
Write-Host "Report ready: $archive"
Write-Host 'This ZIP contains private network metadata. Send it only in the private diagnostic conversation.'
Write-Host 'Open Mosh normally using its usual shortcut. Recording will be off.'
Write-Host 'No private keys, databases or ETL files were copied.'
