$ErrorActionPreference = 'Stop'
$root = Join-Path (Get-Location) 'build/existing-cpu-export'
[void](New-Item -ItemType Directory -Force "$root/tools/PerfViewExtensions", "$root/symbols")
$control = Join-Path (Get-Location) 'build/stack-control/raw/control-cpu/raw'
Copy-Item "$control/tools/PerfView.exe" "$root/tools"
Copy-Item "$control/tools/PerfViewExtensions/ProbeStacks.dll" "$root/tools/PerfViewExtensions"
Copy-Item build/native-symbols/mosh_core.pdb, build/native-symbols/manifest.json "$root/symbols"
Copy-Item "$PSScriptRoot/Export-ExistingCpu.ps1", "$PSScriptRoot/StackPaths.ps1", "$PSScriptRoot/Start-Existing-CPU.cmd", "$PSScriptRoot/Existing-CPU.txt" $root
Copy-Item "$PSScriptRoot/../network-diagnostics/CpuEvents.ps1" $root
$zip = Join-Path (Get-Location) 'build/mosh-existing-cpu-export.zip'
Compress-Archive -Path "$root/*" -DestinationPath $zip
$hash = (Get-FileHash $zip).Hash.ToLowerInvariant()
"$hash  mosh-existing-cpu-export.zip" | Set-Content -Encoding ASCII "$zip.sha256"
