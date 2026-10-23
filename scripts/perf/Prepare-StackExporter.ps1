param([string]$Tool, [switch]$AttributionTest)
$ErrorActionPreference = 'Stop'
$extensions = Join-Path (Split-Path $Tool) 'PerfViewExtensions'
[void](New-Item -ItemType Directory -Force $extensions)
$assemblyName = if ($AttributionTest) { 'ProbeStacksTests.dll' } else { 'ProbeStacks.dll' }
$destination = Join-Path $extensions $assemblyName
if (Test-Path $destination) { exit 0 }
# The checked PerfView binary has already unpacked its own managed libraries.
$roots = @((Join-Path $env:APPDATA 'PerfView'), (Join-Path $env:TEMP 'PerfView'))
$trace = @(Get-ChildItem $roots -Recurse -Filter Microsoft.Diagnostics.Tracing.TraceEvent.dll -ErrorAction SilentlyContinue)
if ($trace.Count -ne 1) { throw "Expected one pinned PerfView TraceEvent library, found $($trace.Count)" }
$support = Split-Path $trace[0].FullName
$references = @($Tool, $trace[0].FullName,
    (Join-Path $support 'Microsoft.Diagnostics.FastSerialization.dll'),
    'System.dll', 'System.Core.dll', 'System.Xml.dll')
$compilerDirectory = [Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()
$facades = @(
    (Join-Path $support 'netstandard.dll'),
    (Join-Path $compilerDirectory 'Facades/netstandard.dll'),
    (Join-Path ${env:ProgramFiles(x86)} 'Reference Assemblies/Microsoft/Framework/.NETFramework/v4.8/Facades/netstandard.dll'),
    (Join-Path ${env:ProgramFiles(x86)} 'Reference Assemblies/Microsoft/Framework/.NETFramework/v4.7.2/Facades/netstandard.dll'))
$facade = @($facades | Where-Object { Test-Path $_ } | Select-Object -First 1)
if ($facade.Count -ne 1) { throw 'The runner is missing its .NET Standard reference facade' }
$references += $facade[0]
# csc accepts an executable assembly reference; PowerShell 5 Add-Type treats
# the PerfView.exe path as an assembly name and rejects it before compilation.
$compileArguments = @('/nologo', '/target:library', "/out:$destination")
$compileArguments += @($references | ForEach-Object { "/reference:$_" })
$compileArguments += Join-Path $PSScriptRoot 'ExportCpuStacks.cs'
if ($AttributionTest) { $compileArguments += Join-Path $PSScriptRoot 'Test-MossAttribution.cs' }
& (Join-Path $compilerDirectory 'csc.exe') @compileArguments
if ($LASTEXITCODE -ne 0) { throw 'PerfView extension compilation failed' }
