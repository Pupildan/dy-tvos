$ErrorActionPreference = 'Continue'
$cfg = Get-Content 'C:\Users\Admin\WorkBuddy\fndanmu-tvos\build-package\swiftfin-fnos\.git\config' -Raw
if ($cfg -match 'x-access-token:([^@]+)@') { $tok = $Matches[1].Trim() } else { throw 'no token' }
$h = @{ Authorization = "Bearer $tok"; 'User-Agent' = 'dy-pipeline'; Accept = 'application/vnd.github+json' }
$jid = $null
# v202 run id
$r = Invoke-RestMethod -Uri 'https://api.github.com/repos/Pupildan/dy-tvos/actions/runs?per_page=3' -Headers $h
foreach ($run in $r.workflow_runs) {
    if ($run.head_sha -match '^1423433') { $v202run = $run.id; break }
}
Write-Output ("V202 RUN " + $v202run + " " + $v202run.GetType().Name)
$jobs = Invoke-RestMethod -Uri ("https://api.github.com/repos/Pupildan/dy-tvos/actions/runs/{0}/jobs" -f $v202run) -Headers $h
$j = $jobs.jobs[0]
$jid = $j.id
Write-Output ("JOB " + $jid + " " + $j.conclusion)
$zip = 'C:\Nbeetok\dy-tvos\_tmp\v202_joblog.zip'
Invoke-WebRequest -Uri ("https://api.github.com/repos/Pupildan/dy-tvos/actions/jobs/{0}/logs" -f $jid) -Headers $h -OutFile $zip -TimeoutSec 120
Write-Output ("zip size: " + (Get-Item $zip).Length)
$log = Get-Content $zip -Raw
$lines = $log -split "`n"
Write-Output ("TOTAL LINES " + $lines.Count)
$hits = $lines | Where-Object { $_ -match 'error:|warning:.*(catalog|icon|brandasset|imagestack)|actool\.notices|no image' } | Select-Object -First 25
$hits | Out-File 'C:\Nbeetok\dy-tvos\_tmp\v202_err.log' -Encoding utf8
Write-Output ("ERR LINES: " + $hits.Count)
