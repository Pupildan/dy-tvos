$ErrorActionPreference = 'Continue'
$cfg = Get-Content 'C:\Users\Admin\WorkBuddy\fndanmu-tvos\build-package\swiftfin-fnos\.git\config' -Raw
if ($cfg -match 'x-access-token:([^@]+)@') { $tok = $Matches[1].Trim() } else { throw 'no token' }
$h = @{ Authorization = "Bearer $tok"; 'User-Agent' = 'dy-pipeline'; Accept = 'application/vnd.github+json' }

# v195 run: 找它的 run id (display_title 含 v195)
$r = Invoke-RestMethod -Uri ("https://api.github.com/repos/Pupildan/dy-tvos/actions/runs?per_page=15") -Headers $h
$v195 = $r.workflow_runs | Where-Object { $_.display_title -match 'v195' } | Select-Object -First 1
Write-Output ("V195 RUN " + $v195.id + " " + $v195.conclusion)
$jid = ($jobs = Invoke-RestMethod -Uri ("https://api.github.com/repos/Pupildan/dy-tvos/actions/runs/{0}/jobs" -f $v195.id) -Headers $h).jobs[0].id
Write-Output ("JOB " + $jid)

$zipPath = 'C:\Nbeetok\dy-tvos\_tmp\v195_joblog.zip'
Invoke-WebRequest -Uri ("https://api.github.com/repos/Pupildan/dy-tvos/actions/jobs/{0}/logs" -f $jid) -Headers $h -OutFile $zipPath
$log = Get-Content $zipPath -Raw
$lines = $log -split "`n"
Write-Output ("TOTAL LINES " + $lines.Count)

# brandassets 编译结果 + APPICON_NAME 相关 + warning
$lines | Where-Object { $_ -match 'AppIcon|brandasset|top.shelf|ASSETCATALOG|app icon|App Icon|\.car|compilation-results' } | Out-File 'C:\Nbeetok\dy-tvos\_tmp\v195_icon.log' -Encoding utf8
Write-Output ("WROTE v195_icon lines: " + (Get-Content 'C:\Nbeetok\dy-tvos\_tmp\v195_icon.log').Count)
