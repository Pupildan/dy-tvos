# v128 log analysis (PS 5.1 compatible)
$log = 'C:\Nbeetok\dy-tvos\output\atv_push.log'
$lines = Get-Content $log
Write-Output ("total_lines=" + $lines.Count)

Write-Output "=== sessions (DYTV launched) ==="
($lines | Select-String -Pattern 'DYTV v\d+ launched').Count

Write-Output "=== novideo per-idx top ==="
$nv = @{}
foreach ($l in $lines) { if ($l -match 'MGR novideo idx=(\d+)') { $k = $Matches[1]; if ($nv.ContainsKey($k)) { $nv[$k]++ } else { $nv[$k] = 1 } } }
$nv.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 8 | ForEach-Object { Write-Output ("  idx=" + $_.Key + " x" + $_.Value) }
Write-Output ("  unique idx with novideo = " + $nv.Count)

Write-Output "=== itemErr texts ==="
$ie = @{}
foreach ($l in $lines) { if ($l -match 'MGR itemErr (.+)$') { $k = $Matches[1]; if ($ie.ContainsKey($k)) { $ie[$k]++ } else { $ie[$k] = 1 } } }
$ie.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 6 | ForEach-Object { Write-Output ("  x" + $_.Value + "  " + $_.Key) }

Write-Output "=== last 5 WATCH repair with following 4 lines ==="
$rIdx = @()
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match 'WATCH repair') { $rIdx += $i } }
$shown = 0
for ($j = $rIdx.Count - 1; $j -ge 0 -and $shown -lt 5; $j--) {
    $i = $rIdx[$j]; $shown++
    Write-Output "  ---"
    $end = [Math]::Min($i + 4, $lines.Count - 1)
    for ($k = $i; $k -le $end; $k++) { Write-Output ("  " + $lines[$k]) }
}

Write-Output "=== redirect age distribution ==="
$ages = @()
foreach ($l in $lines) { if ($l -match 'src=redirect age=(\d+)s') { $ages += [int]$Matches[1] } }
$min = ($ages | Measure-Object -Minimum).Minimum
$max = ($ages | Measure-Object -Maximum).Maximum
Write-Output ("  redirect count=" + $ages.Count + "  min=" + $min + "s max=" + $max + "s")

Write-Output "=== acquire->ready latency ==="
$pending = @{}
$lat = @()
foreach ($l in $lines) {
    if ($l -match '^\[(\d\d:\d\d:\d\d)\] MGR acquire idx=(\d+)') { $pending[$Matches[2]] = $Matches[1] }
    elseif ($l -match '^\[(\d\d:\d\d:\d\d)\] MGR ready idx=(\d+)') {
        $k = $Matches[2]
        if ($pending.ContainsKey($k)) {
            $t0 = [datetime]::ParseExact($pending[$k], 'HH:mm:ss', $null)
            $t1 = [datetime]::ParseExact($Matches[1], 'HH:mm:ss', $null)
            $lat += [int]($t1 - $t0).TotalSeconds
            $pending.Remove($k)
        }
    }
}
if ($lat.Count -gt 0) {
    $m = $lat | Measure-Object -Average -Maximum -Minimum
    $gt3 = ($lat | Where-Object { $_ -gt 3 }).Count
    Write-Output ("  ready latency: n=" + $m.Count + " avg=" + [math]::Round($m.Average,1) + "s max=" + $m.Maximum + "s min=" + $m.Minimum + "s  >3s=" + $gt3)
}
