$ErrorActionPreference = 'Stop'
$root = Join-Path (Get-Location) 'build/stack-control'
[void](New-Item -ItemType Directory -Force $root)
$exe = Join-Path $root 'mosh.exe'
Add-Type -OutputAssembly $exe -OutputType ConsoleApplication -TypeDefinition @'
using System;
public static class StackControl {
    static double value;
    public static void Main() { while (true) value = Math.Sqrt(value + 12345); }
}
'@
$worker = Start-Process $exe -PassThru
try {
    python scripts/perf/stack_control.py $root $worker.Id
    if ($LASTEXITCODE -ne 0) { throw 'Live stack export failed' }
} finally {
    if (-not $worker.HasExited) { $worker.Kill(); $worker.WaitForExit() }
}
