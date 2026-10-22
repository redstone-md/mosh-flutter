# Standalone profiler tools; no application dependency or settings change.
function Get-CpuProfilerTool([string]$Directory, [switch]$GoSymbols) {
    [void](New-Item -ItemType Directory -Force $Directory)
    $name = if ($GoSymbols) { 'GoReSym.exe' } else { 'PerfView.exe' }
    $path = Join-Path $Directory $name
    if ($GoSymbols) {
        $archive = Join-Path $Directory 'goresym.zip'
        Invoke-WebRequest 'https://github.com/mandiant/GoReSym/releases/download/v3.4.1/GoReSym-windows.zip' -OutFile $archive
        $expected = 'c051f182412197d834bd3cbd91424831b7aadb85dfe6548603873672560a8dea'
        if ((Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) { throw 'Symbol tool checksum mismatch' }
        Expand-Archive $archive (Join-Path $Directory 'goresym') -Force
        $file = @(Get-ChildItem (Join-Path $Directory 'goresym') -Recurse -Filter GoReSym.exe)
        if ($file.Count -ne 1) { throw 'Symbol tool missing' }
        Copy-Item $file[0].FullName $path
    } else {
        Invoke-WebRequest 'https://github.com/microsoft/perfview/releases/download/v4.0.0/PerfView.exe' -OutFile $path
        $expected = '270e2ba419b0b2d93c4b15b0851f257edf655c92fe0ad95add3d0b5f6d6aad48'
        if ((Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) { throw 'Profiler checksum mismatch' }
    }
    return $path
}

function Read-CpuModuleTotals([string]$Csv) {
    $modules = @{}; $unresolved = 0.0; $total = 0.0
    foreach ($row in Import-Csv $Csv) {
        if (-not $row.Exc) { continue } # Multiline command-line metadata is not quoted by PerfView.
        $cost = [double]::Parse($row.Exc, [Globalization.CultureInfo]::InvariantCulture)
        if ($cost -le 0) { continue }
        $total += $cost
        if ($row.Name -notmatch '^([^!]+)!') { $unresolved += $cost; continue }
        $module = [IO.Path]::GetFileName($Matches[1])
        if ($module -eq '?') { $unresolved += $cost; continue }
        if (-not $modules.ContainsKey($module)) { $modules[$module] = 0.0 }
        $modules[$module] += $cost
    }
    if ($total -le 0) { throw 'No target CPU samples' }
    return @{
        sampled_weight = $total; unresolved_weight = $unresolved
        modules = @($modules.Keys | ForEach-Object {
            @{ module = $_; weight = $modules[$_]; percent = 100 * $modules[$_] / $total }
        } | Sort-Object { $_.weight } -Descending)
        note = 'Statistical attribution; sampled weights are not process CPU counters.'
    }
}

function Read-CpuInstructionOffsets([string]$Xml, [int]$TargetId, [array]$Modules) {
    $ranges = @($Modules | Sort-Object base)
    [long[]]$starts = @($ranges | ForEach-Object { $_.base })
    $counts = @{}; $unknown = 0; $kernel = 0
    $reader = [Xml.XmlReader]::Create($Xml)
    try {
        while ($reader.Read()) {
            if ($reader.NodeType -ne [Xml.XmlNodeType]::Element -or $reader.Name -ne 'Event') { continue }
            $ip = $reader.GetAttribute('InstructionPointer')
            if (-not $ip -or [int]$reader.GetAttribute('PID') -ne $TargetId) { continue }
            $address = [Convert]::ToUInt64(($ip -replace '^0x', ''), 16)
            if ($address -gt [long]::MaxValue) { $kernel++; continue }
            $index = [Array]::BinarySearch($starts, [long]$address)
            if ($index -lt 0) { $index = -$index - 2 }
            if ($index -lt 0 -or $address -ge ($ranges[$index].base + $ranges[$index].size)) { $unknown++; continue }
            $offset = $address - $ranges[$index].base
            $key = '{0}|{1}' -f $ranges[$index].name, $offset
            if (-not $counts.ContainsKey($key)) { $counts[$key] = 0 }
            $counts[$key]++
        }
    } finally { $reader.Close() }
    return @{
        unmapped_user_samples = $unknown; kernel_samples = $kernel
        instructions = @($counts.Keys | ForEach-Object {
            $parts = $_.Split('|')
            @{ module = $parts[0]; offset = [long]$parts[1]; samples = $counts[$_] }
        } | Sort-Object { $_.samples } -Descending)
    }
}

function Read-GoCpuSymbols([string]$Tool, [string]$Dll, [string]$RawDirectory) {
    $output = Join-Path $RawDirectory 'go-symbols.json'
    & $Tool -d $Dll | Set-Content -Encoding UTF8 $output
    if ($LASTEXITCODE -ne 0) { throw 'Go symbol recovery failed' }
    $symbols = Get-Content $output -Raw | ConvertFrom-Json
    $bytes = [IO.File]::ReadAllBytes($Dll)
    $pe = [BitConverter]::ToInt32($bytes, 60)
    if ([BitConverter]::ToUInt16($bytes, ($pe + 24)) -ne 0x20b) { throw 'Expected a 64-bit PE' }
    $imageBase = [BitConverter]::ToUInt64($bytes, ($pe + 48))
    return @{
        version = $symbols.Version; image_base = $imageBase
        functions = @(@($symbols.UserFunctions) + @($symbols.StdFunctions) | ForEach-Object {
            @{ name = $_.FullName; start = [long]$_.Start - [long]$imageBase; end = [long]$_.End - [long]$imageBase }
        } | Sort-Object start)
    }
}
