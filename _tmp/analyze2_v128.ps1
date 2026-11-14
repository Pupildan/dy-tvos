# v128 analysis round 2: who returns to idx 69/82
$log = 'C:\Nbeetok\dy-tvos\output\atv_push.log'
$lines = Get-Content $log

Write-Output "=== WATCH events by (type, idx) ==="
$w = @{}
foreach ($l in $lines) {
    if ($l -match 'WATCH (skip|repair|skip-guard|cascade-stop) idx=(\d+)') {
        $k = $Matches[1] + "@" + $Matches[2]
        if ($w.ContainsKey($k)) { $w[$k]++ } else { $w[$k] = 1 }
    }
}
$w.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { Write-Output ("  " + $_.Key + " x" + $_.Value) }

Write-Output "=== engine transitions to 69/82 ==="
foreach ($idx in @('69','82')) {
    $n = ($lines | Select-String -Pattern ("ENGINE next -> index=" + $idx + "$")).Count
    $p = ($lines | Select-String -Pattern ("ENGINE prev -> index=" + $idx + "$")).Count
    $s = ($lines | Select-String -Pattern ("FEEDCOLL scrollTo idx=" + $idx + " ")).Count
    Write-Output ("  idx=$idx : next=$n prev=$p scrollTo=$s")
}

Write-Output "=== first 3 full cycles of idx=69 (WATCH..WATCH) ==="
$events = @()
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match 'WATCH (skip|repair) idx=69') { $events += $i } }
$shown = 0
foreach ($st in $events) {
    if ($shown -ge 3) { break }
    # find the next WATCH event after st
    $nxt = -1
    for ($k = $st + 1; $k -lt $lines.Count; $k++) { if ($lines[$k] -match 'WATCH (skip|repair) idx=69') { $nxt = $k; break } }
    if ($nxt -lt 0) { break }
    if ($nxt - $st -gt 30) { $shown++; Write-Output "  --- cycle ---"
        for ($k = $st; $k -le [Math]::Min($st + 28, $lines.Count - 1); $k++) { Write-Output ("  " + $lines[$k]) } }
}
