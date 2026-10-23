param([string]$Tool)
$ErrorActionPreference = 'Stop'
$extensions = Join-Path (Split-Path $Tool) 'PerfViewExtensions'
[void](New-Item -ItemType Directory -Force $extensions)
$destination = Join-Path $extensions 'ProbeStacks.dll'
if (Test-Path $destination) { exit 0 }
# The checked PerfView binary has already unpacked its own managed libraries.
$roots = @((Join-Path $env:APPDATA 'PerfView'), (Join-Path $env:TEMP 'PerfView'))
$trace = @(Get-ChildItem $roots -Recurse -Filter Microsoft.Diagnostics.Tracing.TraceEvent.dll -ErrorAction SilentlyContinue)
if ($trace.Count -ne 1) { throw "Expected one pinned PerfView TraceEvent library, found $($trace.Count)" }
$support = Split-Path $trace[0].FullName
$references = @($Tool, $trace[0].FullName,
    (Join-Path $support 'Microsoft.Diagnostics.FastSerialization.dll'),
    'System.dll', 'System.Core.dll', 'System.Xml.dll')
Add-Type -Path (Join-Path $PSScriptRoot 'ExportCpuStacks.cs') -ReferencedAssemblies $references `
    -OutputAssembly $destination -OutputType Library
