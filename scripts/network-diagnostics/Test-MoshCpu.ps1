param([string]$MossLibrary = '')
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/CpuEvents.ps1"
$root = Join-Path $env:RUNNER_TEMP ('cpu-control-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Force $root)
$exe = Join-Path $root 'MoshCpuControl.exe'
$compiler = [Microsoft.CSharp.CSharpCodeProvider]::new()
$options = [CodeDom.Compiler.CompilerParameters]::new()
$options.GenerateExecutable = $true
$options.OutputAssembly = $exe
$options.CompilerOptions = '/platform:x64'
$result = $compiler.CompileAssemblyFromSource($options, 'using System; using System.Runtime.InteropServices; public class CpuControl { [DllImport("kernel32.dll")] static extern bool QueryPerformanceCounter(out long value); public static void Main() { long value; while(true) QueryPerformanceCounter(out value); } }')
if ($result.Errors.HasErrors) { throw ($result.Errors | Out-String) }
$compiler.Dispose()
$child = Start-Process $exe -PassThru
try {
    & "$PSHOME/powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot/Measure-MoshCpu.ps1" -TargetProcessId $child.Id -DurationSeconds 12 -OutputDirectory $root
    if ($LASTEXITCODE -ne 0) { throw 'CPU collector failed' }
    $cpu = Get-Content (Join-Path $root 'cpu-summary.json') -Raw | ConvertFrom-Json
    if ($cpu.sampled_weight -lt 2000) { throw 'Busy process samples missing' }
    $instructions = Get-Content (Join-Path $root 'cpu-instructions.json') -Raw | ConvertFrom-Json
    if (($instructions.instructions | Measure-Object samples -Sum).Sum -lt 100) { throw 'Mapped instruction samples missing' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead((Join-Path $root 'mosh-cpu-report.zip'))
    try {
        $allowed = @('binary-manifest.json','cpu-summary.json','cpu-instructions.json','network-summary.json','process-samples.json')
        foreach ($entry in $zip.Entries) { if ($entry.FullName -notin $allowed) { throw "Unexpected report file: $($entry.FullName)" } }
        if ($zip.Entries.Count -ne $allowed.Count) { throw 'Missing report files' }
    } finally { $zip.Dispose() }
    if ($MossLibrary) {
        $raw = Join-Path $root 'raw'
        $tool = Get-CpuProfilerTool (Join-Path $raw 'tools') -GoSymbols
        $symbols = Read-GoCpuSymbols $tool $MossLibrary $raw
        if ($symbols.functions.Count -lt 1000 -or -not @($symbols.functions | Where-Object { $_.name -like '*moss*mesh*' }).Count) { throw 'Moss function recovery missing' }
        if (@($symbols.functions | Where-Object { $_.start -lt 0 -or $_.end -le $_.start }).Count) { throw 'Invalid relative function addresses' }
        @{ version = $symbols.version; count = $symbols.functions.Count; sha256 = (Get-FileHash $MossLibrary -Algorithm SHA256).Hash } |
            ConvertTo-Json | Set-Content (Join-Path $root 'symbol-control.json')
    }
    Write-Host "CPU toolkit verified: $root"
} finally {
    if (-not $child.HasExited) { $child.Kill(); $child.WaitForExit() }
}
