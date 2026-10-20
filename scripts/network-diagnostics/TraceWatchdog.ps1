param(
    [ValidatePattern('^MoshNetwork-[a-f0-9]{32}$')][string]$SessionName,
    [ValidateRange(35, 330)][int]$DeadlineSeconds
)
# An independent deadline also stops the owned trace if its collector is closed.
Start-Sleep -Seconds $DeadlineSeconds
& logman stop $SessionName -ets | Out-Null
