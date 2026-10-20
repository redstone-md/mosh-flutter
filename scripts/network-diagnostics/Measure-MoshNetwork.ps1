param(
    [int]$TargetProcessId = 0,
    [ValidateRange(5, 300)][int]$DurationSeconds = 120,
    [string]$OutputDirectory = '',
    [switch]$Elevated
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/NetworkEvents.ps1"
. "$PSScriptRoot/TraceControl.ps1"

if ($TargetProcessId -eq 0) {
    $candidates = @(Get-Process -Name mosh -ErrorAction SilentlyContinue)
    if ($candidates.Count -ne 1) { throw 'Open one Mosh instance before starting diagnostics.' }
    $TargetProcessId = $candidates[0].Id
}
$target = Get-Process -Id $TargetProcessId
$processStarted = $target.StartTime.ToUniversalTime()
if (-not $OutputDirectory) {
    $stamp = [datetime]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $OutputDirectory = Join-Path $env:LOCALAPPDATA "Mosh/Diagnostics/network-$stamp"
}
[void](New-Item -ItemType Directory -Force $OutputDirectory)
$OutputDirectory = (Resolve-Path $OutputDirectory).Path
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if ($Elevated) { throw 'Administrator rights are required for the Windows network trace.' }
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath),
        '-TargetProcessId', $TargetProcessId, '-DurationSeconds', $DurationSeconds,
        '-OutputDirectory', ('"{0}"' -f $OutputDirectory), '-Elevated')
    $collector = Start-Process "$PSHOME/powershell.exe" -Verb RunAs -ArgumentList $arguments -Wait -PassThru
    exit $collector.ExitCode
}

$schema = Get-MoshNetworkSchema
$session = 'MoshNetwork-' + [guid]::NewGuid().ToString('N')
$trace = Join-Path $OutputDirectory 'private-network.etl'
$sessionStarted = $false
$watchdog = $null
$loss = $null
$samples = @()
try {
    $traceStart = & logman create trace $session -p $MoshNetworkProvider '0xffffffffffffffff' 5 `
        -o $trace -f bincirc -max 128 -nb 16 64 -bs 64 -ets
    if ($LASTEXITCODE -ne 0) { throw "Windows could not start the network trace: $traceStart" }
    $sessionStarted = $true
    $watchdog = Start-Process "$PSHOME/powershell.exe" -WindowStyle Hidden -PassThru -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}/TraceWatchdog.ps1"' -f $PSScriptRoot),
        '-SessionName', $session, '-DeadlineSeconds', ($DurationSeconds + 30))
    $startedAt = [datetime]::UtcNow
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    Send-MoshTraceControlPackets
    Write-Host 'Collecting Mosh network usage. Leave the problem chat open or reproduce the idle state.'
    Write-Host "Duration: $DurationSeconds seconds. Mosh continues running normally."
    while ($watch.Elapsed.TotalSeconds -lt $DurationSeconds) {
        $target.Refresh()
        if ($target.HasExited) { break }
        if ($target.StartTime.ToUniversalTime() -ne $processStarted) { throw 'The target process changed.' }
        $samples += @{
            second = [math]::Round($watch.Elapsed.TotalSeconds, 3)
            cpu_ms = $target.TotalProcessorTime.TotalMilliseconds
            working_set_bytes = $target.WorkingSet64
            has_window = ($target.MainWindowHandle -ne [IntPtr]::Zero)
        }
        Start-Sleep -Seconds 1
    }
    $endControlStarted = [datetime]::UtcNow
    Send-MoshTraceControlPackets
} finally {
    if ($sessionStarted) {
        $loss = Stop-MoshNetworkTrace $session
        $sessionStarted = $false
    }
    if ($null -ne $watchdog -and -not $watchdog.HasExited) { $watchdog.Kill(); $watchdog.WaitForExit() }
}
$stoppedAt = [datetime]::UtcNow
$totals = New-MoshNetworkTotals
$controlStartBytes = [uint64]0
$controlEndBytes = [uint64]0
$collectorPid = $PID
$records = 0
Get-WinEvent -Path $trace -Oldest -ErrorAction Stop | ForEach-Object {
    $event = Convert-MoshNetworkEvent $_ $schema
    if ($null -eq $event) { return }
    $records++
    if ($event.process_id -eq $collectorPid -and $event.protocol -eq 'udp' -and $event.loopback) {
        if ($event.timestamp -lt $endControlStarted) { $controlStartBytes += $event.bytes }
        else { $controlEndBytes += $event.bytes }
    }
    if ($event.process_id -eq $TargetProcessId) { Add-MoshNetworkEvent $totals $event $startedAt }
}
if ($controlStartBytes -lt 1280 -or $controlEndBytes -lt 1280) {
    throw 'The trace does not cover both control bursts; no complete measurement was produced.'
}
$elapsed = ($stoppedAt - $startedAt).TotalSeconds
$report = @{
    format_version = 1; process_id = $TargetProcessId
    process_start_utc = $processStarted.ToString('o')
    started_utc = $startedAt.ToString('o'); stopped_utc = $stoppedAt.ToString('o')
    elapsed_seconds = $elapsed; windows_version = [Environment]::OSVersion.Version.ToString()
    provider = $MoshNetworkProvider; control_validated = $true; loss = $loss
    complete = ($loss.events_lost -eq 0 -and $loss.log_buffers_lost -eq 0 -and $loss.realtime_buffers_lost -eq 0)
    measurement = 'Kernel-Network size fields; send/recv and retransmit are separate; includes loopback separately'
    network = Export-MoshNetworkTotals $totals
}
$report | ConvertTo-Json -Depth 9 | Set-Content (Join-Path $OutputDirectory 'network-summary.json') -Encoding UTF8
$samples | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $OutputDirectory 'process-samples.json') -Encoding UTF8
$files = @('network-summary.json', 'process-samples.json') | ForEach-Object { Join-Path $OutputDirectory $_ }
$archive = Join-Path $OutputDirectory 'mosh-network-report.zip'
Compress-Archive -Path $files -DestinationPath $archive -Force
Write-Host "Report ready: $archive"
Write-Host 'The ZIP contains only this process byte totals, anonymized peers and resource samples.'
Write-Host 'The raw ETL stays local and is not included in the ZIP.'
if (-not $report.complete) { Write-Warning 'ETW lost events. Report totals are incomplete; loss counters are included.' }
