param([string]$ReportDirectory = '')
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/StackPaths.ps1"
. "$PSScriptRoot/CpuEvents.ps1"
$stage = 'locating the existing report'
try {
    if (-not $ReportDirectory) {
        $ReportDirectory = (Read-Host 'Folder containing the existing CPU report and raw/cpu.etl').Trim('"')
    }
    $ReportDirectory = [Environment]::ExpandEnvironmentVariables($ReportDirectory)
    if (-not (Test-Path (Join-Path $ReportDirectory 'raw/cpu.etl'))) { throw 'Existing CPU trace not found' }
    $stage = 'checking the original build and symbols'
    $manifest = Get-Content (Join-Path $ReportDirectory 'binary-manifest.json') -Raw | ConvertFrom-Json
    $symbols = Get-Content "$PSScriptRoot/symbols/manifest.json" -Raw | ConvertFrom-Json
    foreach ($binary in $symbols.binaries) {
        $found = @($manifest.binaries | Where-Object { $_.name -eq $binary.name -and $_.sha256 -eq $binary.sha256 })
        if ($found.Count -ne 1) { throw 'This report uses a different application build' }
    }
    if ($manifest.process_name -ne 'mosh' -or $manifest.pid -le 0) { throw 'Invalid process manifest' }
    $pdb = (Get-FileHash "$PSScriptRoot/symbols/mosh_core.pdb").Hash.ToLowerInvariant()
    if ($pdb -ne $symbols.pdb_sha256) { throw 'PDB checksum mismatch' }
    $tool = "$PSScriptRoot/tools/PerfView.exe"
    if ((Get-FileHash $tool).Hash.ToLowerInvariant() -ne '270e2ba419b0b2d93c4b15b0851f257edf655c92fe0ad95add3d0b5f6d6aad48') { throw 'Profiler checksum mismatch' }
    Unblock-File -LiteralPath "$PSScriptRoot/tools/PerfViewExtensions/ProbeStacks.dll"
    $output = Join-Path $PSScriptRoot ('output/' + [datetime]::UtcNow.ToString('yyyyMMdd-HHmmss'))
    $raw = Join-Path $output 'raw'; [void](New-Item -ItemType Directory -Force $raw)
    $stage = 'copying the existing trace'
    Copy-Item (Join-Path $ReportDirectory 'raw/cpu.etl') "$raw/cpu.etl"
    $env:_NT_SYMBOL_PATH = "$PSScriptRoot/symbols;srv*$raw/symbol-cache*https://msdl.microsoft.com/download/symbols"
    Write-Host 'Processing the existing trace. Mosh can keep running. No new recording is made.'
    $stage = 'resolving caller stacks'
    Invoke-CpuProfiler $tool @('/AcceptEula', '/NoGui', '/ShowUnknownAddresses', "/LogFile:$raw/symbols.log",
        'userCommand', 'ProbeStacks.SaveExactCpuStacks', "$raw/cpu.etl", [string]$manifest.pid,
        "$raw/callers.xml.zip") "$raw/console.log"
    $stage = 'creating the sanitized report'
    $result = Export-SelectedStackPaths "$raw/callers.xml.zip" $manifest.pid "$output/callers.json"
    @{ runtime_source = $symbols.commit; pid = $manifest.pid; sampled_weight = $result.sampled_weight
        trace_sha256 = (Get-FileHash "$raw/cpu.etl").Hash.ToLowerInvariant(); binaries = $symbols.binaries
    } | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 "$output/identity.json"
    $zip = Join-Path $output 'mosh-callers-report.zip'
    Compress-Archive -Path "$output/callers.json", "$output/identity.json" -DestinationPath $zip
    Write-Host "Ready. Send this ZIP: $zip"
    Write-Host 'Raw system trace, full paths, process arguments and profiler logs stay local.'
} catch {
    Write-Host ('Export failed during ' + $stage + ': ' + $_.Exception.GetType().Name)
    Write-Host 'Keep this window open and send the error text. Do not send raw/.'
    exit 1
}
