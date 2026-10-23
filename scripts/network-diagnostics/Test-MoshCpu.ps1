param([string]$MossLibrary = '')
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/CpuEvents.ps1"
$root = Join-Path $env:RUNNER_TEMP ('cpu-control-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Force $root)
$exe = Join-Path $root 'MoshCpuControl.exe'
if ($MossLibrary) { Copy-Item $MossLibrary (Join-Path $root 'moss.dll') }
$compiler = [Microsoft.CSharp.CSharpCodeProvider]::new()
$options = [CodeDom.Compiler.CompilerParameters]::new()
$options.GenerateExecutable = $true
$options.OutputAssembly = $exe
$options.CompilerOptions = '/platform:x64'
[void]$options.ReferencedAssemblies.Add('System.dll')
$result = $compiler.CompileAssemblyFromSource($options, @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
public class CpuControl {
    [DllImport("kernel32.dll")] static extern bool QueryPerformanceCounter(out long value);
    public static void Main(string[] args) {
        var clock = Stopwatch.StartNew();
        long value;
        while (true) {
            long end = clock.ElapsedMilliseconds + 10;
            do { QueryPerformanceCounter(out value); } while (clock.ElapsedMilliseconds < end);
            if (args.Length == 0) System.Threading.Thread.Sleep(15);
        }
    }
}
'@)
if ($result.Errors.HasErrors) { throw ($result.Errors | Out-String) }
$compiler.Dispose()
$child = Start-Process $exe -PassThru
$noise = Start-Process $exe -ArgumentList 'noise' -PassThru
try {
    & "$PSHOME/powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot/Measure-MoshCpu.ps1" -TargetProcessId $child.Id -DurationSeconds 12 -OutputDirectory $root
    if ($LASTEXITCODE -ne 0) { throw 'CPU collector failed' }
    $cpu = Get-Content (Join-Path $root 'cpu-summary.json') -Raw | ConvertFrom-Json
    if ($cpu.sampled_weight -lt 1000) { throw 'Busy process samples missing' }
    $instructions = Get-Content (Join-Path $root 'cpu-instructions.json') -Raw | ConvertFrom-Json
    if (($instructions.instructions | Measure-Object samples -Sum).Sum -lt 100) { throw 'Mapped instruction samples missing' }
    $rawWeight = [long]$instructions.kernel_samples + [long]$instructions.unmapped_user_samples +
        [long]($instructions.instructions | Measure-Object samples -Sum).Sum
    if ($cpu.sampled_weight -ne $rawWeight) { throw 'CPU summary must reconcile with the exact PID, excluding busier same-name processes' }
    $child.Refresh(); $noise.Refresh()
    if ($noise.TotalProcessorTime -le $child.TotalProcessorTime) { throw 'Same-name control must be busier than the selected target' }
    $nativeWeight = ($cpu.modules | Where-Object { $_.module -in @('ntdll','kernelbase','kernel32','clr') } | Measure-Object weight -Sum).Sum
    if (($instructions.instructions | Measure-Object samples -Sum).Sum -lt 0.9 * $nativeWeight) { throw 'Native module and instruction attribution disagree' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead((Join-Path $root 'mosh-cpu-report.zip'))
    try {
        $allowed = @('binary-manifest.json','cpu-summary.json','cpu-instructions.json','network-summary.json','process-samples.json')
        if ($MossLibrary) { $allowed += 'go-functions.json' }
        if (@($zip.Entries | Where-Object { $_.FullName -notin $allowed }).Count) { throw 'Unexpected report files' }
        if ($zip.Entries.Count -ne $allowed.Count) { throw 'Missing report files' }
    } finally { $zip.Dispose() }
    if ($MossLibrary) {
        $symbols = Get-Content (Join-Path $root 'go-functions.json') -Raw | ConvertFrom-Json
        if ($symbols.functions.Count -lt 1000 -or -not @($symbols.functions | Where-Object { $_.name -like '*moss*mesh*' }).Count) { throw 'Moss function recovery missing' }
        if (@($symbols.functions | Where-Object { $_.start -lt 0 -or $_.end -le $_.start }).Count) { throw 'Invalid relative function addresses' }
        @{ version = $symbols.version; count = $symbols.functions.Count; sha256 = (Get-FileHash $MossLibrary -Algorithm SHA256).Hash } |
            ConvertTo-Json | Set-Content (Join-Path $root 'symbol-control.json')
    }
    Write-Host "CPU toolkit verified: $root"
} finally {
    foreach ($process in @($child, $noise)) {
        if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
    }
}
