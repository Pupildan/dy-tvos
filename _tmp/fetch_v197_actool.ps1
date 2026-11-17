$ErrorActionPreference = 'Continue'
$cfg = Get-Content 'C:\Users\Admin\WorkBuddy\fndanmu-tvos\build-package\swiftfin-fnos\.git\config' -Raw
if ($cfg -match 'x-access-token:([^@]+)@') { $tok = $Matches[1].Trim() } else { throw 'no token' }
$h = @{ Authorization = "Bearer $tok"; 'User-Agent' = 'dy-pipeline'; Accept = 'application/vnd.github+json' }

# v197 成功 run
$runId = 44091652919
$jobs = Invoke-RestMethod -Uri ("https://api.github.com/repos/Pupildan/dy-tvos/actions/runs/{0}/jobs" -f $runId) -Headers $h
$j = $jobs.jobs | Select-Object -First 1
Write-Output ("JOB " + $j.id + " " + $j.name + " " + $j.conclusion)

# 拉完整构建日志
$log = Invoke-RestMethod -Uri $j.logs_url -Headers $h
$lines = $log -split "`n"
Write-Output ("TOTAL LINES " + $lines.Count)

# 只留 actool / Assets / AppIcon / brandasset / .car 相关行
$out = 'C:\Nbeetok\dy-tvos\_tmp\v197_actool.log'
$lines | Where-Object { $_ -match 'actool|Assets\.xcassets|AppIcon|brandasset|\.car|com\.apple\.actool|top.shelf|no image|Icon' } | Out-File $out -Encoding utf8
Write-Output ("WROTE " + $out + " (" + (Get-Content $out).Count + " lines)")
