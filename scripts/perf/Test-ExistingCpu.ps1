$ErrorActionPreference = 'Stop'
$root = Join-Path (Get-Location) 'build/portable-replay-fixture'
$bundle = Join-Path (Get-Location) 'build/existing-cpu-export'

function Invoke-DownloadedBundle {
    $helper = Join-Path $bundle 'tools/PerfViewExtensions/ProbeStacks.dll'
    $hash = (Get-FileHash $helper).Hash
    Set-Content -LiteralPath $helper -Stream Zone.Identifier -Encoding ASCII -Value "[ZoneTransfer]`r`nZoneId=3"
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = Join-Path $env:SystemRoot 'System32/cmd.exe'
    $info.Arguments = '/d /c Start-Existing-CPU.cmd -ReportDirectory "' + $root + '"'
    $info.WorkingDirectory = $bundle
    $info.UseShellExecute = $false
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.EnvironmentVariables['PSModulePath'] = (& pwsh -NoProfile -Command '$env:PSModulePath' | Out-String).Trim()
    $child = [Diagnostics.Process]::new(); $child.StartInfo = $info
    try {
        [void]$child.Start()
        $child.StandardInput.WriteLine(); $child.StandardInput.Close()
        $child.StandardOutput.ReadToEnd() | Set-Content "$root/raw/launcher.stdout.txt"
        $child.StandardError.ReadToEnd() | Set-Content "$root/raw/launcher.stderr.txt"
        $child.WaitForExit()
        if ($child.ExitCode -ne 0) { throw 'Downloaded bundle failed through the PowerShell 7 CMD launcher' }
    } finally { $child.Dispose() }
    if ((Get-FileHash $helper).Hash -ne $hash) { throw 'Helper content changed during unblocking' }
    if (Get-Item -LiteralPath $helper -Stream Zone.Identifier -ErrorAction SilentlyContinue) { throw 'Helper is still blocked' }
}

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
    Invoke-DownloadedBundle
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
