$ErrorActionPreference = 'Continue'
$cfg = Get-Content 'C:\Users\Admin\WorkBuddy\fndanmu-tvos\build-package\swiftfin-fnos\.git\config' -Raw
if ($cfg -match 'x-access-token:([^@]+)@') { $tok = $Matches[1].Trim() } else { throw 'no token' }
$h = @{ Authorization = "Bearer $tok"; 'User-Agent' = 'dy-pipeline'; Accept = 'application/vnd.github+json' }

$runId = 44091652919   # v197 success run
$jobs = Invoke-RestMethod -Uri ("https://api.github.com/repos/Pupildan/dy-tvos/actions/runs/{0}/jobs" -f $runId) -Headers $h
$j = $jobs.jobs | Select-Object -First 1
Write-Output ("JOB " + $j.id + " " + $j.conclusion)

# logs_url 可能需要从 job 对象单独取，或用 jobs 列表里的字段
$jid = $j.id
$out = 'C:\Nbeetok\dy-tvos\_tmp\v197_build.log'
# 直接下载 job 日志（zip），解出文本
$zipPath = 'C:\Nbeetok\dy-tvos\_tmp\v197_joblog.zip'
Invoke-WebRequest -Uri ("https://api.github.com/repos/Pupildan/dy-tvos/actions/jobs/{0}/logs" -f $jid) -Headers $h -OutFile $zipPath
$log = Get-Content $zipPath -Raw
$lines = $log -split "`n"
Write-Output ("TOTAL LINES " + $lines.Count)

$lines | Where-Object { $_ -match 'actool|Assets\.xcassets|AppIcon|brandasset|\.car|com\.apple\.actool|top.shelf|no image|Icon|warning.*catalog|error.*catalog' } | Out-File 'C:\Nbeetok\dy-tvos\_tmp\v197_actool.log' -Encoding utf8
Write-Output ("WROTE actool lines: " + (Get-Content 'C:\Nbeetok\dy-tvos\_tmp\v197_actool.log').Count)
