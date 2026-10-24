$MoshNetworkProvider = 'Microsoft-Windows-Kernel-Network'

# Discover field positions from the installed provider, including payload PID.
function Get-MoshNetworkSchema {
    $result = @{}
    $provider = Get-WinEvent -ListProvider $MoshNetworkProvider -ErrorAction Stop
    foreach ($event in $provider.Events) {
        $opcode = $event.Opcode.Name
        if ($opcode -notmatch '_(SEND|RECV|RETRANSMIT)(UDP)?$') { continue }
        $direction = $Matches[1].ToLowerInvariant()
        $protocol = if ($event.Task.Name -match 'UDPIP$') { 'udp' } else { 'tcp' }
        [xml]$template = $event.Template
        $fields = @($template.SelectNodes('//*[local-name()="data"]') | ForEach-Object { $_.name })
        foreach ($required in @('PID', 'size', 'saddr', 'daddr', 'sport', 'dport')) {
            if ($fields -notcontains $required) { throw "Network provider is missing $required" }
        }
        $result[[int]$event.Id] = @{
            fields = $fields; direction = $direction; protocol = $protocol
        }
    }
    if ($result.Count -lt 8) { throw 'Unsupported Windows network event schema' }
    return $result
}

function Convert-MoshNetworkEvent($Event, [hashtable]$Schema) {
    if ($Event.ProviderName -ne $MoshNetworkProvider) { return $null }
    $description = $Schema[[int]$Event.Id]
    if ($null -eq $description) { return $null }
    $values = @{}
    for ($index = 0; $index -lt $description.fields.Count; $index++) {
        $values[$description.fields[$index]] = $Event.Properties[$index].Value
    }
    if ($null -eq $values.PID -or $null -eq $values.size -or $null -eq $Event.TimeCreated) {
        throw 'Network event has no payload PID, size or timestamp'
    }
    $remoteField = if ($description.direction -eq 'recv') { 'saddr' } else { 'daddr' }
    $portField = if ($description.direction -eq 'recv') { 'sport' } else { 'dport' }
    $remote = if ($values[$remoteField] -is [byte[]]) {
        [System.Net.IPAddress]::new([byte[]]$values[$remoteField])
    } else {
        [System.Net.IPAddress]::new([long]$values[$remoteField])
    }
    return @{
        process_id = [uint32]$values.PID; bytes = [uint64]$values.size
        direction = $description.direction; protocol = $description.protocol
        timestamp = $Event.TimeCreated.ToUniversalTime()
        loopback = [System.Net.IPAddress]::IsLoopback($remote)
        remote_key = ('{0}/{1}/{2}' -f $description.protocol, $remote, $values[$portField])
    }
}

function New-MoshNetworkTotals {
    return @{ bytes = @{}; seconds = @{}; peers = @{}; events = 0 }
}

# Keep endpoint values in memory; export only ordinal peer aliases and byte totals.
function Add-MoshNetworkEvent([hashtable]$Totals, [hashtable]$Event, [datetime]$StartedAt) {
    if ($Event.timestamp -lt $StartedAt) { return }
    $key = '{0}_{1}_{2}' -f $Event.protocol, $Event.direction, $(if ($Event.loopback) { 'loopback' } else { 'external' })
    if (-not $Totals.bytes.ContainsKey($key)) { $Totals.bytes[$key] = [uint64]0 }
    $Totals.bytes[$key] += $Event.bytes
    $second = [int][math]::Floor(($Event.timestamp - $StartedAt).TotalSeconds)
    if (-not $Totals.seconds.ContainsKey($second)) { $Totals.seconds[$second] = @{} }
    $bucket = $Totals.seconds[$second]
    if (-not $bucket.ContainsKey($key)) { $bucket[$key] = [uint64]0 }
    $bucket[$key] += $Event.bytes
    if (-not $Totals.peers.ContainsKey($Event.remote_key)) {
        $Totals.peers[$Event.remote_key] = @{
            peer = 'peer_{0:D3}' -f ($Totals.peers.Count + 1)
            protocol = $Event.protocol; loopback = $Event.loopback; bytes = [uint64]0
        }
    }
    $Totals.peers[$Event.remote_key].bytes += $Event.bytes
    $Totals.events++
}

function Export-MoshNetworkTotals([hashtable]$Totals) {
    return @{
        event_count = $Totals.events; reported_bytes = $Totals.bytes
        seconds = @($Totals.seconds.Keys | Sort-Object | ForEach-Object {
            @{ second = $_; reported_bytes = $Totals.seconds[$_] }
        })
        peers = @($Totals.peers.Values | Sort-Object bytes -Descending)
    }
}

function Send-MoshTraceControlPackets {
    $receiver = [System.Net.Sockets.UdpClient]::new(0)
    $sender = [System.Net.Sockets.UdpClient]::new()
    try {
        $receiver.Client.ReceiveTimeout = 2000
        $endpoint = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Loopback, $receiver.Client.LocalEndPoint.Port)
        for ($index = 0; $index -lt 10; $index++) {
            [void]$sender.Send((New-Object byte[] 128), 128, $endpoint)
            $source = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
            [void]$receiver.Receive([ref]$source)
        }
    } finally { $sender.Dispose(); $receiver.Dispose() }
}
