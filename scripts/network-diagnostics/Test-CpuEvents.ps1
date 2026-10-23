$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/CpuEvents.ps1"

function Assert-CpuSample($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$directory = Join-Path $env:RUNNER_TEMP ('cpu-events-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory $directory)
try {
    $xml = Join-Path $directory 'samples.xml'
    @'
<Events>
  <Event PID="17" InstructionPointer="0x1100" />
  <Event PID="17" InstructionPointer="0x1100" />
  <Event PID="42" InstructionPointer="0x1100" />
  <Event PID="42" InstructionPointer="0xfffff80000000000" />
  <Event PID="17" InstructionPointer="0xfffff80000000000" />
  <Event PID="17" InstructionPointer="0x9000" />
  <Event PID="17" />
</Events>
'@ | Set-Content $xml -Encoding UTF8
    $samples = Read-CpuInstructionOffsets $xml 17 @(@{name='Target.DLL';base=0x1000L;size=0x1000L})
    $summary = Read-CpuModuleTotals $samples
    Assert-CpuSample ($summary.sampled_weight -eq 4) 'Exclude foreign PID and non-IP events'
    Assert-CpuSample ($summary.unresolved_weight -eq 1) 'Retain unknown user addresses'
    $target = @($summary.modules | Where-Object { $_.module -eq 'target' })
    Assert-CpuSample ($target.Count -eq 1 -and $target[0].weight -eq 2 -and $target[0].percent -eq 50) 'Attribute mapped target samples once'
    $kernel = @($summary.modules | Where-Object { $_.module -eq '[kernel]' })
    Assert-CpuSample ($kernel.Count -eq 1 -and $kernel[0].weight -eq 1) 'Keep target kernel samples separate'
    $known = ($summary.modules | Measure-Object weight -Sum).Sum
    Assert-CpuSample ($known + $summary.unresolved_weight -eq $summary.sampled_weight) 'Conserve sample totals'

    $summary = Read-CpuModuleTotals @{instructions=@();kernel_samples=2;unmapped_user_samples=0}
    Assert-CpuSample ($summary.sampled_weight -eq 2 -and $summary.modules[0].module -eq '[kernel]') 'Retain kernel-only captures'
    $summary = Read-CpuModuleTotals @{instructions=@();kernel_samples=0;unmapped_user_samples=3}
    Assert-CpuSample ($summary.sampled_weight -eq 3 -and $summary.unresolved_weight -eq 3 -and $summary.modules.Count -eq 0) 'Retain unmapped-only captures'
    $refused = $false
    try { Read-CpuModuleTotals @{instructions=@();kernel_samples=0;unmapped_user_samples=0} } catch { $refused = $true }
    Assert-CpuSample $refused 'Refuse empty captures'
    Write-Host 'Exact-PID CPU samples, module totals and unknown/kernel buckets passed.'
} finally { Remove-Item $directory -Recurse -Force }
