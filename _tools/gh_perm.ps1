# DY pipeline: check fine-grained PAT permissions (repo list + create capability)
$ErrorActionPreference = 'Continue'
$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$ips = @('140.82.113.3','140.82.114.3','140.82.112.3','140.82.116.3','140.82.121.3','20.27.177.113')
$cfg = Get-Content 'C:\Users\Admin\WorkBuddy\fndanmu-tvos\build-package\swiftfin-fnos\.git\config' -Raw
if ($cfg -match 'x-access-token:([^@]+)@') { $tok = $Matches[1].Trim() } else { throw 'no token' }
$h = @{ Authorization = "Bearer $tok"; Accept = 'application/vnd.github+json'; 'User-Agent' = 'dy-pipeline' }

function Set-ApiHost([string]$ip) {
    $c = Get-Content $hostsPath
    $c = $c | ForEach-Object { if ($_ -match '^\s*\S+\s+api\.github\.com\s*$') { ($ip + ' api.github.com') } else { $_ } }
    $c | Set-Content $hostsPath -Encoding ASCII
    ipconfig /flushdns | Out-Null
}

function Invoke-GhApi([string]$method, [string]$uri, $body) {
    for ($i = 0; $i -lt $ips.Count; $i++) {
        Set-ApiHost $ips[$i]
        try {
            $params = @{ Method=$method; Uri=$uri; Headers=$h; TimeoutSec=20 }
            if ($body) { $params.ContentType='application/json'; $params.Body=($body|ConvertTo-Json) }
            return Invoke-RestMethod @params
        } catch {
            $msg = $_.Exception.Message
            $code = $_.Exception.Response.StatusCode.value__
            Write-Output ("  api try " + $ips[$i] + " status=" + $code + " msg=" + $msg)
            if ($code -ne 0 -and $code -ne $null) { return @{ _status = $code; _err = $msg } }
        }
    }
    return @{ _status = 0; _err = 'unreachable' }
}

# List repos the token can see (fine-grained PATs only list accessible ones)
$r = Invoke-GhApi 'GET' 'https://api.github.com/user/repos?per_page=100&sort=updated' $null
if ($r._status) { Write-Output ("repos list status=" + $r._status) }
else {
    Write-Output ("accessible repo count=" + $r.Count)
    $r | ForEach-Object { Write-Output ("  " + $_.full_name + " perms(admin=" + $_.permissions.admin + ")") }
}

Write-Output 'RESULT perm_probe_done'
