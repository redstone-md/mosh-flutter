$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/NetworkEvents.ps1"

function Assert-MoshDiagnostic($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$schema = Get-MoshNetworkSchema
foreach ($id in @(10, 11, 26, 27, 42, 43, 58, 59)) {
    Assert-MoshDiagnostic ($schema.ContainsKey($id)) "Missing installed-provider event $id"
}
$description = $schema[42]
$values = @{ PID = [uint32]987; size = [uint32]128; saddr = [uint32]16777343
    daddr = [uint32]67305985; sport = [uint16]5000; dport = [uint16]6000 }
$record = [pscustomobject]@{
    ProviderName = $MoshNetworkProvider; Id = 42; ProcessId = 123
    TimeCreated = [datetime]::UtcNow
    Properties = @($description.fields | ForEach-Object { [pscustomobject]@{Value=$values[$_]} })
}
$event = Convert-MoshNetworkEvent $record $schema
Assert-MoshDiagnostic ($event.process_id -eq 987) 'Use payload PID, not the kernel/header PID'
$totals = New-MoshNetworkTotals
Add-MoshNetworkEvent $totals $event $record.TimeCreated.ToUniversalTime()
$summary = Export-MoshNetworkTotals $totals | ConvertTo-Json -Depth 8
Assert-MoshDiagnostic ($totals.bytes['udp_send_external'] -eq 128) 'Count the event size once'
Assert-MoshDiagnostic ($summary -notmatch '1\.2\.3\.4|67305985|remote_key') 'Exported peers must be anonymous'
$unrelated = [pscustomobject]@{ProviderName='Other';Id=42}
Assert-MoshDiagnostic ($null -eq (Convert-MoshNetworkEvent $unrelated $schema)) 'Ignore unrelated providers'
Write-Host 'Installed schema, payload-PID attribution and safe export checks passed.'

$testDirectory = Join-Path $env:RUNNER_TEMP ('mosh-net-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory $testDirectory)
$trafficScript = Join-Path $testDirectory 'traffic.ps1'
@'
param([int]$Size, [int]$Delay)
$receiver = [System.Net.Sockets.UdpClient]::new(0)
$sender = [System.Net.Sockets.UdpClient]::new()
$address = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Loopback, $receiver.Client.LocalEndPoint.Port)
$end = [datetime]::UtcNow.AddSeconds(40)
try {
    while ([datetime]::UtcNow -lt $end) {
        [void]$sender.Send((New-Object byte[] $Size), $Size, $address)
        $remote = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
        [void]$receiver.Receive([ref]$remote)
        Start-Sleep -Milliseconds $Delay
    }
} finally { $sender.Dispose(); $receiver.Dispose() }
'@ | Set-Content $trafficScript -Encoding UTF8
$target = $null
$noise = $null
try {
    $target = Start-Process "$PSHOME/powershell.exe" -ArgumentList @('-NoProfile', '-File', ('"{0}"' -f $trafficScript), '128', '50') -PassThru
    $noise = Start-Process "$PSHOME/powershell.exe" -ArgumentList @('-NoProfile', '-File', ('"{0}"' -f $trafficScript), '1024', '5') -PassThru
    & "$PSScriptRoot/Measure-MoshNetwork.ps1" -TargetProcessId $target.Id -DurationSeconds 5 -OutputDirectory $testDirectory
    $result = Get-Content (Join-Path $testDirectory 'network-summary.json') -Raw | ConvertFrom-Json
    Assert-MoshDiagnostic $result.control_validated 'Live ETW control packets must be seen'
    Assert-MoshDiagnostic $result.complete 'Both control bursts and a lossless trace are required'
    $network = $result.network.reported_bytes
    Assert-MoshDiagnostic ($network.udp_send_loopback -ge 1280) 'Target UDP sends must be measured'
    Assert-MoshDiagnostic ($network.udp_recv_loopback -ge 1280) 'Target UDP receives must be measured'
    Assert-MoshDiagnostic ($network.udp_send_loopback -lt 100000) 'Foreign-process noise must be excluded'
    Assert-MoshDiagnostic ($result.loss.events_lost -eq 0) 'The live test must not lose trace events'
    Write-Host ('Real target UDP capture passed: tx={0}, rx={1}; unrelated traffic excluded.' -f $network.udp_send_loopback, $network.udp_recv_loopback)
} finally {
    foreach ($child in @($target, $noise)) {
        if ($null -ne $child -and -not $child.HasExited) { $child.Kill(); $child.WaitForExit() }
    }
}

# Failure details survive a child console closing, and stay outside the report ZIP.
$failure = Start-Process "$PSHOME/powershell.exe" -Wait -PassThru -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}/Measure-MoshNetwork.ps1"' -f $PSScriptRoot),
    '-TargetProcessId', 2147483647, '-OutputDirectory', ('"{0}"' -f $testDirectory))
Assert-MoshDiagnostic ($failure.ExitCode -ne 0) 'Missing process must fail'
Assert-MoshDiagnostic ((Get-Item (Join-Path $testDirectory 'collector-error.txt')).Length -gt 0) 'Persist the child failure message'
