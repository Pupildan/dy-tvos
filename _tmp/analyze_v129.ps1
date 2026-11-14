# v129 session analysis
$log = 'C:\Nbeetok\dy-tvos\output\atv_push.log'
$lines = Get-Content $log

# locate v129 session start
$start = -1
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match 'DYTV v129 launched') { $start = $i } }
Write-Output ("v129 session starts at raw line " + $start + " / " + $lines.Count)
$sess = New-Object System.Collections.Generic.List[string]
for ($i = $start; $i -lt $lines.Count; $i++) { $sess.Add($lines[$i]) }

# dedupe (connection backlog duplicates)
$seen = @{}
$uniq = New-Object System.Collections.Generic.List[string]
foreach ($l in $sess) {
    if ($l -match '^\d\d:\d\d:\d\d  (.+)$') { $core = $Matches[1] } else { $core = $l }
    if (-not $seen.ContainsKey($core)) { $seen[$core] = 1; $uniq.Add($core) }
}
Write-Output ("session raw=" + $sess.Count + "  unique=" + $uniq.Count + "  dup_factor=" + [math]::Round($sess.Count / [Math]::Max(1,$uniq.Count), 1))

Write-Output "=== counters ==="
foreach ($pat in @('FEED skip-item','reason=type','reason=nodur','FEED item ','MGR acquire','MGR ready','MGR novideo','MGR itemErr','WATCH repair','WATCH skip idx','WATCH skip-guard','WATCH healthy','WATCH cascade-stop','url_static','src=redirect age','src=redirect forced','COVER retry','FEED mobile GET','filtered=','ENGINE merge','scrollTo')) {
    $n = ($uniq | Select-String -SimpleMatch $pat).Count
    Write-Output ("  " + $pat.PadRight(20) + "= " + $n)
}

Write-Output "=== skip-item lines (all) ==="
$uniq | Select-String -SimpleMatch 'FEED skip-item' | ForEach-Object { Write-Output ("  " + $_.Line) }

Write-Output "=== itemErr / novideo / WATCH (all) ==="
$uniq | Select-String -Pattern 'MGR (itemErr|novideo)|WATCH (repair|skip idx|cascade)' | ForEach-Object { Write-Output ("  " + $_.Line) }

Write-Output "=== type value distribution on kept items ==="
$th = @{}
foreach ($l in $uniq) { if ($l -match 'FEED item a\[\d+\] id=\d+ type=(\d+)') { $k = $Matches[1]; if ($th.ContainsKey($k)) { $th[$k]++ } else { $th[$k] = 1 } } }
$th.GetEnumerator() | Sort-Object Name | ForEach-Object { Write-Output ("  type=" + $_.Key + " x" + $_.Value) }

Write-Output "=== dur distribution kept items ==="
$dh = @{}
foreach ($l in $uniq) { if ($l -match 'FEED item .* dur=(\d+)$') { $d = [long]$Matches[1]; $k = if ($d -le 2) { 'dur<=2' } elseif ($d -lt 2000) { 'dur<2s' } else { 'dur>=2s' }; if ($dh.ContainsKey($k)) { $dh[$k]++ } else { $dh[$k] = 1 } } }
$dh.GetEnumerator() | Sort-Object Name | ForEach-Object { Write-Output ("  " + $_.Key + " x" + $_.Value) }

Write-Output "=== acquire->ready latency ==="
$pending = @{}
$lat = @()
foreach ($l in $uniq) {
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
    Write-Output ("  n=" + $m.Count + " avg=" + [math]::Round($m.Average,1) + "s max=" + $m.Maximum + "s  >3s=" + $gt3)
}

Write-Output "=== consecutive duplicate scrollTo lines (potential double-call issue) ==="
$d = 0
for ($i = 1; $i -lt $uniq.Count; $i++) {
    if ($uniq[$i] -match 'FEEDCOLL scrollTo' -and $uniq[$i] -eq $uniq[$i-1]) { $d++ }
}
Write-Output ("  duplicate consecutive scrollTo pairs = " + $d)

Write-Output "=== time span ==="
$ts = @()
foreach ($l in $uniq) { if ($l -match '^\[(\d\d:\d\d:\d\d)\]') { $ts += $Matches[1] } }
if ($ts.Count -gt 0) { Write-Output ("  " + $ts[0] + " .. " + $ts[$ts.Count-1] + "  (n=" + $ts.Count + ")") }
