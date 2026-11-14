# find FEED item lines for pages fetched around 16:49:5x-16:50:0x (the pages containing idx=69/82)
$log = 'C:\Nbeetok\dy-tvos\output\atv_push.log'
$lines = Get-Content $log
$seen = @{}
$uniq = New-Object System.Collections.Generic.List[string]
foreach ($l in $lines) {
    if ($l -match '^\d\d:\d\d:\d\d  (.+)$') { $core = $Matches[1] } else { $core = $l }
    if (-not $seen.ContainsKey($core)) { $seen[$core] = 1; $uniq.Add($core) }
}
Write-Output "=== GET + usable lines 16:49-16:50 (window around idx=69/82 pages) ==="
foreach ($l in $uniq) {
    if ($l -match '^\[(16:49:5\d|16:50:0\d)\]' -and ($l -match 'FEED mobile GET|FEED mobile page|ENGINE merge')) { Write-Output ("  " + $l) }
}
Write-Output ""
Write-Output "=== FEED item lines of those pages ==="
foreach ($l in $uniq) {
    if ($l -match '^\[(16:49:5\d|16:50:0\d)\]' -and $l -match 'FEED item') { Write-Output ("  " + $l) }
}
