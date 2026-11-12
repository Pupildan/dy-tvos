# DY: fetch failing job logs for a CI run of Pupildan/dy-tvos, grep compile errors
param([string]$RunId = '')
$ErrorActionPreference = 'Continue'
. 'C:\Nbeetok\dy-tvos\_tools\dy_common.ps1'
$cfg = Get-Content 'C:\Users\Admin\WorkBuddy\fndanmu-tvos\build-package\swiftfin-fnos\.git\config' -Raw
if ($cfg -match 'x-access-token:([^@]+)@') { $tok = $Matches[1].Trim() } else { throw 'no token' }
$h = @{ Authorization = "Bearer $tok"; Accept = 'application/vnd.github+json'; 'User-Agent'='dy-pipeline' }

if (-not $RunId) { Write-Output 'need -RunId'; exit 1 }
$ip = Resolve-GhHost 'api.github.com' $script:GH_IPS
$jobs = Invoke-RestMethod -Uri "https://api.github.com/repos/Pupildan/dy-tvos/actions/runs/$RunId/jobs" -Headers $h -TimeoutSec 20
foreach ($job in $jobs.jobs) {
    Write-Output ("JOB id=" + $job.id + " name=" + $job.name + " concl=" + $job.conclusion)
    $logDir = 'C:\Nbeetok\dy-tvos\_tmp\cilog'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $logPath = Join-Path $logDir ("job_" + $job.id + ".log")
    $ip = Resolve-GhHost 'api.github.com' $script:GH_IPS
    try {
        Invoke-WebRequest -Uri ("https://api.github.com/repos/Pupildan/dy-tvos/actions/jobs/" + $job.id + "/logs") -Headers $h -OutFile $logPath -TimeoutSec 60
    } catch { Write-Output ("  log fetch fail: " + $_.Exception.Message); continue }
    Write-Output "=== error: / error lines ==="
    Select-String -Path $logPath -Pattern 'error:|error \[' | Select-Object -First 40 | ForEach-Object { Write-Output $_.Line }
}
Write-Output 'RESULT fetch_errors_done'
