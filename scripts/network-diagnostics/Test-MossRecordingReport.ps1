$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/MossRecording.ps1"
$directory = Join-Path ([IO.Path]::GetTempPath()) ('mosh report ' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory $directory)
$recording = Join-Path $directory 'moss-debug-123.mossrec'
'{"metric":"event","data":{"kind":"node.start"}}' | Set-Content $recording
$culture = [Threading.Thread]::CurrentThread.CurrentCulture
try {
    [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('ru-RU')
    $before = [datetime]::UtcNow
    # An invalid Windows epoch and the reported negative duration must not reach the report.
    $summary = @{
        started_utc = $before.ToString('o')
        stopped_utc = [datetime]::FromFileTimeUtc(0).ToString('o')
        observed_seconds = -13437016951.4671
    }
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    Start-Sleep -Milliseconds 25
    $archive = Save-MoshRecordingReport $recording $summary $watch
    $after = [datetime]::UtcNow
    $output = Join-Path $directory 'unpacked'
    Expand-Archive $archive $output
    $files = @(Get-ChildItem $output -File | Sort-Object Name)
    if (($files.Name -join ',') -ne 'moss-debug-123.mossrec,moss-runtime-summary.json') {
        throw 'Archive must contain only the recorder file and summary.'
    }
    $result = Get-Content (Join-Path $output 'moss-runtime-summary.json') -Raw | ConvertFrom-Json
    $stopped = ([datetime]$result.stopped_utc).ToUniversalTime()
    if ($stopped -lt $before -or $stopped -gt $after) { throw 'Report must use the observed completion UTC.' }
    if ($watch.IsRunning -or $result.observed_seconds -le 0 -or
        [math]::Abs($result.observed_seconds - $watch.Elapsed.TotalSeconds) -gt 0.000001) {
        throw 'Report duration must preserve fractional monotonic elapsed seconds.'
    }
    if ((Get-Content (Join-Path $output 'moss-debug-123.mossrec') -Raw) -ne
        (Get-Content $recording -Raw)) { throw 'Recording content must be preserved.' }
    Write-Host 'Moss report passed: invalid timing replaced, fractional duration preserved, exact ZIP contents.'
} finally {
    [Threading.Thread]::CurrentThread.CurrentCulture = $culture
    Remove-Item $directory -Recurse -Force
}
