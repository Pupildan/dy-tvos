$ErrorActionPreference = 'Continue'
$cfg = Get-Content 'C:\Users\Admin\WorkBuddy\fndanmu-tvos\build-package\swiftfin-fnos\.git\config' -Raw
if ($cfg -match 'x-access-token:([^@]+)@') { $tok = $Matches[1].Trim() } else { throw 'no token' }
$h = @{ Authorization = "Bearer $tok"; 'User-Agent' = 'dy-pipeline'; Accept = 'application/vnd.github+json' }

$runId = 44111888314   # v200
$jid = ($jobs = Invoke-RestMethod -Uri ("https://api.github.com/repos/Pupildan/dy-tvos/actions/runs/{0}/jobs" -f $runId) -Headers $h).jobs[0].id
Write-Output ("JOB " + $jid)
$zipPath = 'C:\Nbeetok\dy-tvos\_tmp\v200_joblog.zip'
Invoke-WebRequest -Uri ("https://api.github.com/repos/Pupildan/dy-tvos/actions/jobs/{0}/logs" -f $jid) -Headers $h -OutFile $zipPath
$log = Get-Content $zipPath -Raw
$lines = $log -split "`n"
Write-Output ("TOTAL LINES " + $lines.Count)
# actool --app-icon 参数 + 所有 warning/notice
$out = 'C:\Nbeetok\dy-tvos\_tmp\v200_actool.log'
$sb = New-Object System.Text.StringBuilder
for ($i=0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'actool .*--compile|actool\.notices|actool\.compilation-results|warning:|error:.*catalog|app-icon') {
        $end = [Math]::Min($i + 3, $lines.Count - 1)
        for ($k=$i; $k -le $end; $k++) { [void]$sb.AppendLine($lines[$k]) }
        [void]$sb.AppendLine('----')
    }
}
$sb.ToString() | Out-File $out -Encoding utf8
Write-Output ("WROTE " + $out)
