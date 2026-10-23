$ErrorActionPreference = 'Stop'
$root = Join-Path (Get-Location) 'build/portable-replay-fixture'
$bundle = Join-Path (Get-Location) 'build/existing-cpu-export'
$worker = Start-Process "$env:IDLE_APP/mosh.exe" -PassThru
try {
    $deadline = [datetime]::UtcNow.AddSeconds(30)
    do {
        Start-Sleep -Milliseconds 200
        $worker.Refresh()
        if ($worker.HasExited -or [datetime]::UtcNow -gt $deadline) { throw 'Owned GUI failed to open' }
    } while (-not $worker.MainWindowHandle)
    & "$PSScriptRoot/../network-diagnostics/Measure-MoshCpu.ps1" -TargetProcessId $worker.Id `
        -DurationSeconds 12 -OutputDirectory $root
    $before = (Get-FileHash "$root/raw/cpu.etl").Hash
    & "$bundle/Export-ExistingCpu.ps1" -ReportDirectory $root
    $after = (Get-FileHash "$root/raw/cpu.etl").Hash
    if ($before -ne $after) { throw 'Exporter changed its input trace' }
    $zip = @(Get-ChildItem "$bundle/output" -Recurse -Filter mosh-callers-report.zip)
    if ($zip.Count -ne 1) { throw 'Portable report missing' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($zip[0].FullName)
    try {
        if (($archive.Entries.FullName | Sort-Object) -join ',' -ne 'callers.json,identity.json') { throw 'Unexpected portable ZIP entries' }
    } finally { $archive.Dispose() }
    $summary = Get-Content "$root/cpu-summary.json" -Raw | ConvertFrom-Json
    $callers = Get-Content (Join-Path $zip[0].DirectoryName 'callers.json') -Raw | ConvertFrom-Json
    if ($callers.pid -ne $worker.Id -or $callers.sampled_weight -ne $summary.sampled_weight) { throw 'Portable PID/weight mismatch' }
    Write-Host 'Portable reprocessing of an existing exact-release trace passed; input unchanged.'
} finally {
    if (-not $worker.HasExited) { $worker.Kill(); $worker.WaitForExit() }
}
