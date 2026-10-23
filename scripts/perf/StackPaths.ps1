# Portable reader for the pinned PerfView XML format; raw metadata stays local.
function Convert-StackFrame([string]$Value) {
    if ($Value -match '^Process(?:32|64)?\s+\S+\s+\((\d+)\)(?:\s|$)') { return '[selected process]' }
    if ($Value -match '^Thread \((\d+)\)') { return '[thread ' + $Matches[1] + ']' }
    $bang = $Value.IndexOf('!')
    if ($bang -ge 0) { return [IO.Path]::GetFileName($Value.Substring(0, $bang)) + $Value.Substring($bang) }
    return [IO.Path]::GetFileName($Value)
}

function Read-StackPath($Sample, $Frames, $Stacks) {
    $cursor = [int]$Sample.StackID
    $seen = [Collections.Generic.HashSet[int]]::new()
    $path = [Collections.Generic.List[string]]::new()
    $processes = [Collections.Generic.List[int]]::new()
    while ($cursor -ge 0) {
        if (-not $seen.Add($cursor) -or $seen.Count -gt 512) { throw 'Cyclic or overlong stack' }
        if (-not $Stacks.ContainsKey($cursor)) { throw 'Missing stack ID' }
        $stack = $Stacks[$cursor]
        if (-not $Frames.ContainsKey([int]$stack.FrameID)) { throw 'Missing frame ID' }
        $text = $Frames[[int]$stack.FrameID]
        if ($text -match '^Process(?:32|64)?\s+\S+\s+\((\d+)\)(?:\s|$)') {
            $processes.Add([int]$Matches[1])
        }
        $path.Add((Convert-StackFrame $text))
        $cursor = [int]$stack.CallerID
    }
    $metric = if ($Sample.HasAttribute('Metric')) {
        [double]::Parse($Sample.Metric, [Globalization.CultureInfo]::InvariantCulture)
    } else { 1.0 }
    if ($metric -le 0 -or [double]::IsNaN($metric) -or [double]::IsInfinity($metric)) { throw 'Invalid stack weight' }
    return @{ frames = $path.ToArray(); processes = $processes.ToArray(); weight = $metric }
}

function Read-SelectedStackPaths([xml]$Document, [int]$TargetId) {
    $frames = @{}; $stacks = @{}; $skipped = @{}
    $paths = [Collections.Hashtable]::new([StringComparer]::Ordinal)
    foreach ($frame in $Document.SelectNodes('//Frame')) { $frames[[int]$frame.ID] = $frame.InnerText }
    foreach ($stack in $Document.SelectNodes('//Stack')) { $stacks[[int]$stack.ID] = $stack }
    foreach ($sample in $Document.SelectNodes('//Sample')) {
        $row = Read-StackPath $sample $frames $stacks
        if ($row.processes.Count -ne 1 -or $row.processes[0] -ne $TargetId) {
            $kind = if ($row.processes.Count) { 'foreign' } else { 'without_process' }
            $skipped[$kind] += $row.weight
            continue
        }
        $key = ConvertTo-Json -InputObject @($row.frames) -Compress
        if (-not $paths.ContainsKey($key)) { $paths[$key] = @{ frames = @($row.frames); weight = 0.0 } }
        $paths[$key].weight += $row.weight
    }
    if ($paths.Count -eq 0) { throw 'No exact-PID caller stacks' }
    $weight = ($paths.Values | ForEach-Object { $_.weight } | Measure-Object -Sum).Sum
    return @{ pid = $TargetId; sampled_weight = $weight; skipped_weight = $skipped
        paths = @($paths.Values | Sort-Object { $_.weight } -Descending)
        note = 'Exact-PID paths. Unwinds may be incomplete. Thread names, process arguments and module paths removed.' }
}

function Export-SelectedStackPaths([string]$Source, [int]$TargetId, [string]$Output) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($Source)
    $reader = $null
    try {
        $entries = @($archive.Entries | Where-Object { $_.Name.EndsWith('.xml') })
        if ($entries.Count -ne 1) { throw 'Expected one stack source' }
        $reader = [IO.StreamReader]::new($entries[0].Open())
        $result = Read-SelectedStackPaths ([xml]$reader.ReadToEnd()) $TargetId
        $result | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $Output
        return $result
    } finally {
        if ($reader) { $reader.Dispose() }
        $archive.Dispose()
    }
}
