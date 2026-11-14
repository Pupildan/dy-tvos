# v129: repair outcomes + page filtered distribution + tail
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

Write-Output "=== each WATCH repair: context +-6 lines (recovery check) ==="
for ($i = 0; $i -lt $uniq.Count; $i++) {
    if ($uniq[$i] -match 'WATCH repair') {
        Write-Output "  ---"
        $a = [Math]::Max(0, $i - 2)
        $b = [Math]::Min($i + 7, $uniq.Count - 1)
        for ($k = $a; $k -le $b; $k++) { Write-Output ("  " + $uniq[$k]) }
    }
}

Write-Output "=== per-page filtered values ==="
foreach ($l in $uniq) { if ($l -match 'FEED mobile page .*filtered=(\d+)') { Write-Output ("  " + $Matches[1]) } } 

Write-Output "=== last 12 lines of session ==="
for ($i = [Math]::Max(0, $uniq.Count - 12); $i -lt $uniq.Count; $i++) { Write-Output ("  " + $uniq[$i]) }
