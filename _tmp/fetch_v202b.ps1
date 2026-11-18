$ErrorActionPreference = 'Continue'
$cfg = Get-Content 'C:\Users\Admin\WorkBuddy\fndanmu-tvos\build-package\swiftfin-fnos\.git\config' -Raw
if ($cfg -match 'x-access-token:([^@]+)@') { $tok = $Matches[1].Trim() } else { throw 'no token' }
$h = @{ Authorization = "Bearer $tok"; 'User-Agent' = 'dy-pipeline'; Accept = 'application/vnd.github+json' }
$zip = 'C:\Nbeetok\dy-tvos\_tmp\v202b_joblog.zip'
Invoke-WebRequest -Uri 'https://api.github.com/repos/Pupildan/dy-tvos/actions/jobs/134172032161/logs' -Headers $h -OutFile $zip -TimeoutSec 90
Write-Output ("zip: " + (Get-Item $zip).Length)
$log = Get-Content $zip -Raw
$lines = $log -split "`n"
Write-Output ("LINES " + $lines.Count)
# actool 段全部(命令+notices+results)
$hits = $lines | Where-Object { $_ -match 'actool|com\.apple\.actool|imagestack|App Icon|brandasset|warning|notice' } | Select-Object -First 40
$hits | Out-File 'C:\Nbeetok\dy-tvos\_tmp\v202b_actool.log' -Encoding utf8
Write-Output ("WROTE " + $hits.Count)
