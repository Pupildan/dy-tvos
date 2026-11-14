# v129 cold-start timeline: first 35 unique lines
$log = 'C:\Nbeetok\dy-tvos\output\atv_push.log'
$lines = Get-Content $log
$start = -1
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match 'DYTV v129 launched') { $start = $i } }
$seen = @{}
$uniq = New-Object System.Collections.Generic.List[string]
for ($i = $start; $i -lt $lines.Count; $i++) {
    $l = $lines[$i]
    if ($l -match '^\d\d:\d\d:\d\d  (.+)$') { $core = $Matches[1] } else { $core = $l }
    if (-not $seen.ContainsKey($core)) { $seen[$core] = 1; $uniq.Add($core) }
}
for ($i = 0; $i -lt [Math]::Min(38, $uniq.Count); $i++) { Write-Output ("  " + $uniq[$i]) }
