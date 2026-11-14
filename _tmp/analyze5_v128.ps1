# dur distribution across whole unique log
$log = 'C:\Nbeetok\dy-tvos\output\atv_push.log'
$lines = Get-Content $log
$seen = @{}
$uniq = New-Object System.Collections.Generic.List[string]
foreach ($l in $lines) {
    if ($l -match '^\d\d:\d\d:\d\d  (.+)$') { $core = $Matches[1] } else { $core = $l }
    if (-not $seen.ContainsKey($core)) { $seen[$core] = 1; $uniq.Add($core) }
}
$hist = @{}
$total = 0
foreach ($l in $uniq) {
    if ($l -match 'FEED item a\[\d+\] id=\d+ static=(\w+) redirect=(\w+) dur=(\d+)') {
        $total++
        $d = [long]$Matches[3]
        if ($d -eq 0) { $k = 'dur=0' } elseif ($d -le 2) { $k = 'dur<=2' } elseif ($d -lt 1000) { $k = 'dur<1s' } elseif ($d -lt 60000) { $k = '1s-60s' } else { $k = '>60s' }
        if ($hist.ContainsKey($k)) { $hist[$k]++ } else { $hist[$k] = 1 }
    }
}
Write-Output ("FEED item total=" + $total)
$hist.GetEnumerator() | Sort-Object Name | ForEach-Object { Write-Output ("  " + $_.Key + " = " + $_.Value) }
Write-Output ""
Write-Output "=== all dur=0 / dur<=2 item lines ==="
foreach ($l in $uniq) { if ($l -match 'FEED item .* dur=(\d+)$') { if ([long]$Matches[1] -le 2) { Write-Output ("  " + $l) } } }
