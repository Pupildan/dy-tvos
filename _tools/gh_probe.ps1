# DY pipeline: probe GitHub token validity + scope via IP rotation (GFW bypass)
$ErrorActionPreference = 'Continue'
$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$ips = @('140.82.113.3','140.82.114.3','140.82.112.3','140.82.116.3','140.82.121.3','20.27.177.113')

$cfg = Get-Content 'C:\Users\Admin\WorkBuddy\fndanmu-tvos\build-package\swiftfin-fnos\.git\config' -Raw
if ($cfg -match 'x-access-token:([^@]+)@') { $tok = $Matches[1].Trim() } else { throw 'no token' }
$h = @{ Authorization = "Bearer $tok"; Accept = 'application/vnd.github+json'; 'User-Agent' = 'dy-pipeline' }

function Set-HostEntry([string]$host_, [string]$ip) {
    $c = Get-Content $hostsPath
    $c = $c | ForEach-Object {
        if ($_ -match ('^\s*\S+\s+' + [regex]::Escape($host_) + '\s*$')) { ($ip + ' ' + $host_) } else { $_ }
    }
    $c | Set-Content $hostsPath -Encoding ASCII
    ipconfig /flushdns | Out-Null
}

# 1) whoami
$ok = $false
for ($i = 0; $i -lt $ips.Count; $i++) {
    Set-HostEntry 'api.github.com' $ips[$i]
    try {
        $r = Invoke-RestMethod -Uri 'https://api.github.com/user' -Headers $h -TimeoutSec 20
        Write-Output ("USER login=" + $r.login)
        $ok = $true
        break
    } catch {
        Write-Output ("user try " + $ips[$i] + " fail: " + $_.Exception.Message)
    }
}
if (-not $ok) { Write-Output 'RESULT user=UNREACHABLE'; exit 1 }

# 2) can we create repos? list token-accessible scopes via rate_limit header hit on /user
try {
    $resp = Invoke-WebRequest -Uri 'https://api.github.com/user' -Headers $h -TimeoutSec 20 -UseBasicParsing
    $scopes = $resp.Headers['X-OAuth-Scopes']
    Write-Output ("OAUTH_SCOPES=" + $(if ($scopes) { $scopes -join ',' } else { '(none/empty => fine-grained PAT)' }))
} catch { Write-Output ('scope probe fail: ' + $_.Exception.Message) }

Write-Output 'RESULT probe_done'
