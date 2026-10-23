$ErrorActionPreference = 'Stop'

function Test-MossOffsets([string]$Root) {
    $callers = Get-Content "$Root/control-callers.json" -Raw | ConvertFrom-Json
    $frames = @($callers.paths | ForEach-Object { $_.frames } | Sort-Object -Unique)
    if (-not ($frames -match '^moss!\+0x[0-9a-f]+$')) { throw 'Moss instruction offsets were lost' }
    if ($frames -contains 'moss!?') { throw 'Unresolved Moss frames still discard their addresses' }
    $raw = Get-Content "$Root/control-cpu-instructions.json" -Raw | ConvertFrom-Json
    $instructions = @{}
    foreach ($entry in $raw.instructions) {
        if ($entry.module -eq 'moss.dll') { $instructions[[long]$entry.offset] = $entry.samples }
    }
    $leaves = @{}
    foreach ($path in $callers.paths) {
        $leaf = [regex]::Match([string]$path.frames[0], '^moss!\+0x([0-9a-f]+)$')
        if (-not $leaf.Success) { continue }
        $offset = [Convert]::ToInt64($leaf.Groups[1].Value, 16)
        $leaves[$offset] += $path.weight
    }
    if (-not $leaves.Count) { throw 'No native Moss leaf samples' }
    foreach ($offset in $leaves.Keys) {
        if ($leaves[$offset] -ne $instructions[$offset]) { throw 'Moss stack RVA differs from raw instruction attribution' }
    }
    Write-Host 'Original Moss DLL RVAs match exact-PID raw instruction samples.'
}

$root = Join-Path (Get-Location) 'build/stack-control'
[void](New-Item -ItemType Directory -Force $root)
$exe = Join-Path $root 'mosh.exe'
$withMoss = $env:IDLE_APP -and (Test-Path "$env:IDLE_APP/moss.dll")
if ($withMoss) { Copy-Item "$env:IDLE_APP/moss.dll" $root }
Add-Type -OutputAssembly $exe -OutputType ConsoleApplication -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
public static class StackControl {
    static double value;
    [DllImport("moss.dll", EntryPoint="Moss_Version", CallingConvention=CallingConvention.Cdecl)]
    static extern IntPtr Version();
    [DllImport("moss.dll", EntryPoint="Moss_Free", CallingConvention=CallingConvention.Cdecl)]
    static extern void Free(IntPtr value);
    public static void Main() {
        bool withMoss = File.Exists("moss.dll");
        while (true) {
            if (withMoss) Free(Version());
            value = Math.Sqrt(value + 12345);
        }
    }
}
'@
$worker = Start-Process $exe -WorkingDirectory $root -PassThru
try {
    python scripts/perf/stack_control.py $root $worker.Id
    if ($LASTEXITCODE -ne 0) { throw 'Live stack export failed' }
    & "$PSScriptRoot/Test-StackPaths.ps1" -XmlZip "$root/raw/control-cpu/raw/cpu.perfView.xml.zip" `
        -TargetId $worker.Id -PythonResult "$root/control-callers.json"
    if ($withMoss) {
        Test-MossOffsets $root
    }
} finally {
    if (-not $worker.HasExited) { $worker.Kill(); $worker.WaitForExit() }
}
