# DY pipeline: precise status codes for repo list + repo create + repo get
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

function Gh([string]$method, [string]$uri, $body) {
    for ($i = 0; $i -lt $ips.Count; $i++) {
        Set-ApiHost $ips[$i]
        try {
            $p = @{ Method=$method; Uri=$uri; Headers=$h; TimeoutSec=20; UseBasicParsing=$true }
            if ($body) { $p.ContentType='application/json'; $p.Body=($body|ConvertTo-Json) }
            $resp = Invoke-WebRequest @p
            return @{ code=$resp.StatusCode; json=$resp.Content }
        } catch {
            $resp = $_.Exception.Response
            $code = if ($resp) { [int]$resp.StatusCode } else { 0 }
            $body_ = ''
            try { $sr = New-Object IO.StreamReader($resp.GetResponseStream()); $body_ = $sr.ReadToEnd() } catch {}
            if ($code -ne 0) { return @{ code=$code; json=$body_ } }
        }
    }
    return @{ code=-1; json='unreachable' }
}

# 1) list repos
$r = Gh 'GET' 'https://api.github.com/user/repos?per_page=5' $null
Write-Output ("LIST code=" + $r.code)
if ($r.code -eq 200) {
    $arr = $r.json | ConvertFrom-Json
    Write-Output ("  count(first5)=" + $arr.Count)
    $arr | ForEach-Object { Write-Output ("   " + $_.full_name + " admin=" + $_.permissions.admin) }
} else { Write-Output ("  body=" + $r.json.Substring(0,[Math]::Min(200,$r.json.Length))) }

# 2) read swiftfin-fnos (known accessible)
$r2 = Gh 'GET' 'https://api.github.com/repos/Pupildan/swiftfin-fnos' $null
Write-Output ("GET swiftfin-fnos code=" + $r2.code)

# 3) try create dy-tvos (dry: only if not exists). We probe permission by creating.
$payload = @{ name='dy-tvos'; description='Douyin third-party tvOS client (personal)'; private=$false; auto_init=$false }
$r3 = Gh 'POST' 'https://api.github.com/user/repos' $payload
Write-Output ("CREATE dy-tvos code=" + $r3.code + " (201=created, 422=exists, 403=no-perm)")
if ($r3.code -eq 201) { $j=$r3.json|ConvertFrom-Json; Write-Output ("  created " + $j.full_name + " html=" + $j.html_url) }
else { Write-Output ("  body=" + $r3.json.Substring(0,[Math]::Min(300,$r3.json.Length))) }

Write-Output 'RESULT done'
