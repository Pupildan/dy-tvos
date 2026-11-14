# v128 analysis round 3: dedupe (connection backlog duplicated buffer flushes)
$log = 'C:\Nbeetok\dy-tvos\output\atv_push.log'
$lines = Get-Content $log

# dedupe: keep first occurrence of each identical line (drop collector stamp prefix variance)
$seen = @{}
$uniq = New-Object System.Collections.Generic.List[string]
foreach ($l in $lines) {
    if ($l -match '^\d\d:\d\d:\d\d  (.+)$') { $core = $Matches[1] } else { $core = $l }
    if (-not $seen.ContainsKey($core)) { $seen[$core] = 1; $uniq.Add($core) }
}
Write-Output ("raw=" + $lines.Count + "  unique=" + $uniq.Count)

Write-Output "=== unique event counts ==="
foreach ($pat in @('FEED item ', 'static=ok redirect=none', 'MGR acquire', 'MGR ready', 'src=static age', 'src=redirect age', 'src=redirect forced', 'MGR novideo', 'MGR itemErr', 'WATCH repair', 'WATCH skip idx', 'WATCH skip-guard', 'WATCH healthy', 'COVER retry', 'ENGINE merge', 'FEED mobile GET')) {
    $n = ($uniq | Select-String -SimpleMatch $pat).Count
    Write-Output ("  " + $pat.PadRight(24) + "= " + $n)
}

Write-Output "=== unique WATCH events ==="
$uniq | Select-String -Pattern 'WATCH (skip|repair|skip-guard|cascade-stop) idx=\d+' | ForEach-Object { $_.Line } | ForEach-Object { Write-Output ("  " + $_) }

Write-Output "=== unique itemErr / novideo ==="
$uniq | Select-String -Pattern 'MGR (itemErr|novideo)' | ForEach-Object { Write-Output ("  " + $_.Line) }

Write-Output "=== time span ==="
$ts = @()
foreach ($l in $uniq) { if ($l -match '^\[(\d\d:\d\d:\d\d)\]') { $ts += $Matches[1] } }
if ($ts.Count -gt 0) { Write-Output ("  " + $ts[0] + " .. " + $ts[$ts.Count - 1] + "  (n=" + $ts.Count + ")") }
