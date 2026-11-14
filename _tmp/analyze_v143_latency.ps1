# v143 session: playback trigger latency analysis (scroll -> acquire -> ready)
$log = 'C:\Nbeetok\dy-tvos\output\atv_push.log'
$lines = Get-Content $log
$v = Select-String -Path $log -Pattern 'DYTV v143 launched' | Select-Object -Last 1
$start = if ($v) { $v.LineNumber - 1 } else { $lines.Count - 800 }
$seen = @{}
$uniq = New-Object System.Collections.Generic.List[string]
for ($i = $start; $i -lt $lines.Count; $i++) {
    $l = $lines[$i]
    if ($l -match '^\d\d:\d\d:\d\d  (.+)$') { $core = $Matches[1] } else { $core = $l }
    if (-not $seen.ContainsKey($core)) { $seen[$core] = 1; $uniq.Add($core) }
}
Write-Output ("session lines raw=" + ($lines.Count - $start) + " unique=" + $uniq.Count)

Write-Output "=== timeline: acquire/ready/scroll pairs (first 25) ==="
$pending = @{}
$n = 0
foreach ($l in $uniq) {
    if ($l -match '^\[(\d\d:\d\d:\d\d)\] (MGR url idx=(\d+) src=(\w+)[^\r\n]*)') {
        $pending[$Matches[3]] = @{ t = $Matches[1]; src = $Matches[4] }
    }
    elseif ($l -match '^\[(\d\d:\d\d:\d\d)\] MGR ready idx=(\d+)') {
        $k = $Matches[2]
        if ($pending.ContainsKey($k)) {
            $p = $pending[$k]
            $t0 = [datetime]::ParseExact($p.t, 'HH:mm:ss', $null)
            $t1 = [datetime]::ParseExact($Matches[1], 'HH:mm:ss', $null)
            $lat = ($t1 - $t0).TotalSeconds
            if ($n -lt 25) { Write-Output ("  idx=" + $k + " src=" + $p.src + " url->ready = " + $lat + "s") }
            $n++
            $pending.Remove($k)
        }
    }
}
Write-Output ("total ready events: " + $n)

Write-Output "=== src distribution (url lines) ==="
$h = @{}
foreach ($l in $uniq) { if ($l -match 'MGR url idx=\d+ src=([\w-]+)') { $k = $Matches[1]; if ($h.ContainsKey($k)) { $h[$k]++ } else { $h[$k] = 1 } } }
$h.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { Write-Output ("  " + $_.Key + " = " + $_.Value) }

Write-Output "=== cold-start / defer events ==="
$uniq | Select-String -SimpleMatch 'cold-start' | ForEach-Object { Write-Output ("  " + $_.Line) }

Write-Output "=== scroll->acquire gap sample (FEEDCOLL scrollTo then next acquire) ==="
$prev = $null
$c = 0
foreach ($l in $uniq) {
    if ($l -match '^\[(\d\d:\d\d:\d\d)\] FEEDCOLL scrollTo idx=(\d+) ') {
        if ($prev) { Write-Output ("  scroll@" + $prev.t + " idx=" + $prev.idx + "  ->  next event @" + $Matches[1]) }
        $prev = @{ t = $Matches[1]; idx = $Matches[2] }
        $c++
        if ($c -gt 12) { break }
    }
}
