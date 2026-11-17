# Push retry cycling through ALL GitHub IPs (workaround: Resolve-GhHost always returns first IP)
$ErrorActionPreference = 'Continue'
. 'C:\Nbeetok\dy-tvos\_tools\dy_common.ps1'
$repo = 'C:\Nbeetok\dy-tvos'
$ips = @('140.82.112.3','140.82.114.3','140.82.116.3','140.82.121.3','20.27.177.113','140.82.113.3')
$pushed = $false
foreach ($ip in $ips) {
    if ($pushed) { break }
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        Set-HostIp 'github.com' $ip
        Write-Output ("push try ip=$ip attempt=$attempt")
        & 'C:\Users\Admin\WorkBuddy\fndanmu-tvos\_tools\MinGit\cmd\git.exe' -C $repo push origin main 2>&1 | ForEach-Object { Write-Output ("  " + $_) }
        # verify: remote sha check via API (independent of git connection)
        $cfg = Get-Content 'C:\Users\Admin\WorkBuddy\fndanmu-tvos\build-package\swiftfin-fnos\.git\config' -Raw
        if ($cfg -match 'x-access-token:([^@]+)@') { $tok = $Matches[1].Trim() }
        $h = @{ Authorization = "Bearer $tok"; 'User-Agent' = 'dy-pushcheck' }
        try {
            $b = Invoke-RestMethod -Uri 'https://api.github.com/repos/Pupildan/dy-tvos/branches/main' -Headers $h
            $remote = $b.commit.sha
            $local = (& 'C:\Users\Admin\WorkBuddy\fndanmu-tvos\_tools\MinGit\cmd\git.exe' -C $repo rev-parse HEAD).Trim()
            Write-Output ("  local=$local remote=$remote")
            if ($remote -eq $local) { Write-Output 'PUSHED OK'; $pushed = $true; break }
        } catch { Write-Output ("  api check fail: " + $_.Exception.Message) }
        Start-Sleep -Seconds 3
    }
}
if ($pushed) { exit 0 } else { Write-Output 'ALL PUSH ATTEMPTS FAILED'; exit 1 }
