param(
    [int]$TargetProcessId = 0,
    [ValidateRange(5, 180)][int]$DurationSeconds = 90,
    [string]$OutputDirectory = '',
    [switch]$Elevated
)
$ErrorActionPreference = 'Stop'
trap {
    $message = $_.Exception.Message
    if ($OutputDirectory -and (Test-Path $OutputDirectory -PathType Container)) {
        $message | Set-Content (Join-Path $OutputDirectory 'collector-error.txt') -Encoding UTF8
    }
    Write-Host "CPU recording failed: $message"
    exit 1
}
. "$PSScriptRoot/CpuEvents.ps1"
if (-not [Environment]::Is64BitProcess) { throw 'Run Start-CPU.cmd with 64-bit PowerShell.' }
if ($TargetProcessId -eq 0) {
    $targets = @(Get-Process -Name mosh -ErrorAction SilentlyContinue)
    if ($targets.Count -ne 1) { throw 'Open one Mosh instance first.' }
    $TargetProcessId = $targets[0].Id
}
$target = Get-Process -Id $TargetProcessId
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $env:LOCALAPPDATA ('Mosh/Diagnostics/cpu-' + [datetime]::UtcNow.ToString('yyyyMMdd-HHmmss'))
}
[void](New-Item -ItemType Directory -Force $OutputDirectory)
$OutputDirectory = (Resolve-Path $OutputDirectory).Path
$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if ($Elevated) { throw 'Windows profiling requires administrator rights.' }
    $child = Start-Process "$PSHOME/powershell.exe" -Verb RunAs -Wait -PassThru -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath),
        '-TargetProcessId', $TargetProcessId, '-DurationSeconds', $DurationSeconds,
        '-OutputDirectory', ('"{0}"' -f $OutputDirectory), '-Elevated')
    if ($child.ExitCode -eq 0) { Write-Host "Report ready: $OutputDirectory\mosh-cpu-report.zip" }
    elseif (Test-Path (Join-Path $OutputDirectory 'collector-error.txt')) {
        Get-Content (Join-Path $OutputDirectory 'collector-error.txt') | Write-Host
    }
    exit $child.ExitCode
}
$raw = Join-Path $OutputDirectory 'raw'
[void](New-Item -ItemType Directory -Force $raw)
$tool = Get-CpuProfilerTool (Join-Path $raw 'tools')
$session = 'MoshCpu-' + [guid]::NewGuid().ToString('N')
$trace = Join-Path $raw 'cpu.etl'
$target.Refresh()
$modules = @($target.Modules | ForEach-Object {
    @{ name = $_.ModuleName; base = $_.BaseAddress.ToInt64(); size = $_.ModuleMemorySize }
})
$directory = Split-Path $target.Path
$binaries = @('mosh.exe', 'mosh_core.dll', 'moss.dll', 'flutter_windows.dll', 'data/app.so') | ForEach-Object {
    $file = Join-Path $directory $_
    if (Test-Path $file) { @{ name = $_; sha256 = (Get-FileHash $file -Algorithm SHA256).Hash.ToLowerInvariant()
        last_write_utc = (Get-Item $file).LastWriteTimeUtc.ToString('o') } }
}
$processor = Get-CimInstance Win32_Processor | Select-Object -First 1
@{ process_name = $target.ProcessName; pid = $TargetProcessId; process_started_utc = $target.StartTime.ToUniversalTime().ToString('o')
    windows_version = [Environment]::OSVersion.Version.ToString(); binaries = @($binaries)
    cpu_model = $processor.Name; logical_processors = $processor.NumberOfLogicalProcessors
    perfview = 'v4.0.0'; duration_requested_seconds = $DurationSeconds
} | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 (Join-Path $OutputDirectory 'binary-manifest.json')
$networkPath = Join-Path $raw 'network'
$network = Start-Process "$PSHOME/powershell.exe" -PassThru -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}/Measure-MoshNetwork.ps1"' -f $PSScriptRoot),
    '-TargetProcessId', $TargetProcessId, '-DurationSeconds', $DurationSeconds,
    '-OutputDirectory', ('"{0}"' -f $networkPath))
Write-Host "Sampling this Mosh process for $DurationSeconds seconds. Leave the offline chat open."
Invoke-CpuProfiler $tool @('/AcceptEula','/NoGui','/Zip:false','/NoNGenPdbs','/NoClrRundown','/CircularMB:128',"/SessionName:$session",
    '/KernelEvents:Process+Thread+ImageLoad+Profile','/ClrEvents:None',"/MaxCollectSec:$DurationSeconds",
    "/DataFile:$trace","/LogFile:$raw/collect.log",'collect') (Join-Path $raw 'console.log')
$target.Refresh()
$after = @($target.Modules | ForEach-Object {
    @{ name = $_.ModuleName; base = $_.BaseAddress.ToInt64(); size = $_.ModuleMemorySize }
})
$modules = @(@($modules) + $after | Sort-Object { $_.base } -Unique)
Write-Host 'Recording stopped. Processing CPU and network events; this can take several minutes.'
Invoke-CpuProfiler $tool @('/AcceptEula','/NoGui',"/LogFile:$raw/export.log",'userCommand','SaveCPUStacksAsCsv',
    $trace,$target.ProcessName,'2147483647','GreatestMSec') (Join-Path $raw 'export-console.log')
Read-CpuModuleTotals (Join-Path $raw 'cpu.perfView.csv') | ConvertTo-Json -Depth 7 | Set-Content -Encoding UTF8 (Join-Path $OutputDirectory 'cpu-summary.json')
Invoke-CpuProfiler $tool @('/AcceptEula','/NoGui',"/LogFile:$raw/events.log",'userCommand','DumpEventsAsXml',
    $trace,(Join-Path $raw 'events.xml')) (Join-Path $raw 'events-console.log')
Read-CpuInstructionOffsets (Join-Path $raw 'events.xml') $TargetProcessId $modules | ConvertTo-Json -Depth 7 | Set-Content -Encoding UTF8 (Join-Path $OutputDirectory 'cpu-instructions.json')
$dll = Join-Path $directory 'moss.dll'
if (Test-Path $dll) {
    try {
        $symbols = Get-CpuProfilerTool (Join-Path $raw 'tools') -GoSymbols
        $functions = Read-GoCpuSymbols $symbols $dll $raw
    } catch {
        $functions = @{ status = 'unavailable'; error_type = $_.Exception.GetType().Name }
    }
    $functions | ConvertTo-Json -Depth 7 | Set-Content -Encoding UTF8 (Join-Path $OutputDirectory 'go-functions.json')
}
if (-not $network.WaitForExit(300000)) { throw 'Network processing timed out; raw output stays local.' }
if ($network.ExitCode -ne 0) { throw 'Companion network capture failed' }
Copy-Item (Join-Path $networkPath 'network-summary.json'), (Join-Path $networkPath 'process-samples.json') $OutputDirectory
$summary = Get-Content (Join-Path $OutputDirectory 'network-summary.json') -Raw | ConvertFrom-Json
if (-not $summary.complete -or -not $summary.control_validated) {
    Write-Warning 'Network capture is incomplete; its loss counters are included with the CPU report.'
}
$files = @('binary-manifest.json', 'cpu-summary.json', 'cpu-instructions.json', 'network-summary.json', 'process-samples.json', 'go-functions.json') |
    ForEach-Object { Join-Path $OutputDirectory $_ } | Where-Object { Test-Path $_ }
Compress-Archive -Path $files -DestinationPath (Join-Path $OutputDirectory 'mosh-cpu-report.zip') -Force
Write-Host "Report ready: $OutputDirectory\mosh-cpu-report.zip"
Write-Host 'ZIP: binary hashes, CPU module/instruction aggregates and anonymized network totals. Raw system traces stay in raw/.'
