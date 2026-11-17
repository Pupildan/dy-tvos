$ErrorActionPreference = 'Continue'
$cfg = Get-Content 'C:\Users\Admin\WorkBuddy\fndanmu-tvos\build-package\swiftfin-fnos\.git\config' -Raw
if ($cfg -match 'x-access-token:([^@]+)@') { $tok = $Matches[1].Trim() } else { throw 'no token' }
$h = @{ Authorization = "Bearer $tok"; 'User-Agent' = 'dy-pipeline'; Accept = 'application/vnd.github+json' }

$runId = 44097072064   # v198 success run
$jobs = Invoke-RestMethod -Uri ("https://api.github.com/repos/Pupildan/dy-tvos/actions/runs/{0}/jobs" -f $runId) -Headers $h
$j = $jobs.jobs | Select-Object -First 1
Write-Output ("JOB " + $j.id + " " + $j.conclusion)
$jid = $j.id

$zipPath = 'C:\Nbeetok\dy-tvos\_tmp\v198_joblog.zip'
Invoke-WebRequest -Uri ("https://api.github.com/repos/Pupildan/dy-tvos/actions/jobs/{0}/logs" -f $jid) -Headers $h -OutFile $zipPath
$log = Get-Content $zipPath -Raw
$lines = $log -split "`n"
Write-Output ("TOTAL LINES " + $lines.Count)

# actool 段 + 它的 compilation-results 全文(含 warning/error/空块)
$idx = @()
for ($i=0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match 'com\.apple\.actool\.compilation-results') { $idx += $i } }
Write-Output ("compilation-results blocks at: " + ($idx -join ','))
# 输出每个 results 块后 8 行
$sb = New-Object System.Text.StringBuilder
foreach ($b in $idx) {
    $end = [Math]::Min($b + 8, $lines.Count - 1)
    for ($k=$b; $k -le $end; $k++) { [void]$sb.AppendLine($lines[$k]) }
    [void]$sb.AppendLine('----')
}
$out = 'C:\Nbeetok\dy-tvos\_tmp\v198_actool.log'
$sb.ToString() | Out-File $out -Encoding utf8
Write-Output ("WROTE " + $out)

# 另存 Assets.car / icon 产出相关
$lines | Where-Object { $_ -match 'Assets\.car|AppIcon|icon-1024|appiconset|brandasset|\.car\b' } | Out-File 'C:\Nbeetok\dy-tvos\_tmp\v198_icon.log' -Encoding utf8
Write-Output ("WROTE icon lines: " + (Get-Content 'C:\Nbeetok\dy-tvos\_tmp\v198_icon.log').Count)
