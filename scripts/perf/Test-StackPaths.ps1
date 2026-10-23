param([string]$XmlZip = '', [int]$TargetId = 0, [string]$PythonResult = '')
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/StackPaths.ps1"
[xml]$fixture = @'
<StackSource><Frames>
<Frame ID="0">Process64 mosh (17) Args: private-argument</Frame>
<Frame ID="1">C:\private-module\mosh_core.dll!hot_function</Frame>
<Frame ID="2">Process64 mosh (42) Args: foreign-private-argument</Frame>
<Frame ID="3">Thread (9) CPU=1ms (private-thread-name)</Frame>
</Frames><Stacks>
<Stack ID="0" FrameID="0" CallerID="-1"/>
<Stack ID="1" FrameID="1" CallerID="0"/>
<Stack ID="2" FrameID="2" CallerID="-1"/>
<Stack ID="3" FrameID="1" CallerID="2"/>
<Stack ID="4" FrameID="1" CallerID="-1"/>
<Stack ID="5" FrameID="3" CallerID="0"/>
</Stacks><Samples>
<Sample StackID="1" Metric="2"/><Sample StackID="1"/>
<Sample StackID="3" Metric="8"/><Sample StackID="4" Metric="4"/>
<Sample StackID="5"/>
</Samples></StackSource>
'@
$result = Read-SelectedStackPaths $fixture 17
if ($result.sampled_weight -ne 4 -or $result.skipped_weight.foreign -ne 8 -or $result.skipped_weight.without_process -ne 4) { throw 'Selected PID conservation failed' }
$encoded = $result | ConvertTo-Json -Depth 8
if ($encoded -match 'private-|Args:|CPU=|Process64|C:\\') { throw 'Private metadata escaped' }
if ($encoded -notmatch '\[thread 9\]' -or $encoded -notmatch 'mosh_core.dll!hot_function') { throw 'Useful caller frames lost' }
$failed = $false
try { Read-SelectedStackPaths $fixture 99 | Out-Null } catch { $failed = $true }
if (-not $failed) { throw 'Foreign-only trace accepted' }
$fixture.SelectSingleNode('//Stack[@ID="0"]').SetAttribute('CallerID', '1')
$failed = $false
try { Read-SelectedStackPaths $fixture 17 | Out-Null } catch { $failed = $true }
if (-not $failed) { throw 'Cyclic trace accepted' }
if ($XmlZip) {
    $out = Join-Path (Split-Path $PythonResult) 'portable-callers.json'
    $actual = Export-SelectedStackPaths $XmlZip $TargetId $out
    $expected = Get-Content $PythonResult -Raw | ConvertFrom-Json
    if ($actual.sampled_weight -ne $expected.sampled_weight -or $actual.paths.Count -ne $expected.paths.Count) { throw 'Live portable/reference caller totals differ' }
    if (($actual.skipped_weight.Values | Measure-Object -Sum).Sum -gt 0) { throw 'Live selected-PID trace lost stack weight' }
}
Write-Host 'Portable stack privacy, PID selection, invalid input and live conservation passed.'
