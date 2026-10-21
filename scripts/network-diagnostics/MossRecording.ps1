# Set the diagnostic variable on the child only; leave the parent's environment intact.
function Start-MoshRecordingProcess([string]$ExecutablePath, [string]$RecordDirectory) {
    if (-not $RecordDirectory) { throw 'A private recording directory is required.' }
    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $ExecutablePath
    $start.WorkingDirectory = Split-Path $ExecutablePath
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.EnvironmentVariables['MOSH_DEBUG_RECORD_DIR'] = $RecordDirectory
    # Drain native logs without printing the debug WebSocket's access token.
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($start)
    $process.BeginOutputReadLine()
    $process.BeginErrorReadLine()
    return $process
}

# Wait for the user's normal tray Quit. Never terminate their application.
function Wait-MoshRecordingExit([System.Diagnostics.Process]$Process, [int]$TimeoutSeconds = 300) {
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not $Process.HasExited) {
        if ($watch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
            throw 'Mosh is still running. Use its tray icon > Quit, then run this tool again.'
        }
        Start-Sleep -Milliseconds 250
    }
}

function Wait-MoshRecordingFile(
    [System.Diagnostics.Process]$Process, [string]$Directory, [int]$TimeoutSeconds = 300
) {
    $path = Join-Path $Directory ('moss-debug-{0}.mossrec' -f $Process.Id)
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        if ((Test-Path $path) -and (Get-Item $path).Length -gt 0) { return $path }
        if ($Process.HasExited) { throw 'Mosh exited before its Moss recorder started.' }
        Start-Sleep -Milliseconds 250
    }
    throw 'No Moss recording appeared. Unlock Mosh and open a saved chat before retrying.'
}
