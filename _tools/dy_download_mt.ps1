# DY concurrent artifact download: one background job per GitHub IP, use first that finishes.
# Usage: dy_download_mt.ps1 -ArtifactId <id> -IpaName <name.ipa>
param(
    [Parameter(Mandatory=$true)][string]$ArtifactId,
    [Parameter(Mandatory=$true)][string]$IpaName
)
$ErrorActionPreference = 'Continue'
$cfg = Get-Content 'C:\Users\Admin\WorkBuddy\fndanmu-tvos\build-package\swiftfin-fnos\.git\config' -Raw
if ($cfg -match 'x-access-token:([^@]+)@') { $tok = $Matches[1].Trim() } else { throw 'no token' }
$outDir = 'C:\Nbeetok\dy-tvos\output'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$zipPath = Join-Path $outDir "$IpaName.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force -ErrorAction SilentlyContinue }
$unpack = Join-Path $outDir '_unpack'
if (Test-Path $unpack) { Remove-Item $unpack -Recurse -Force -ErrorAction SilentlyContinue }

# GitHub API IPs (dy_common.ps1 GH_IPS) -- race one download job per IP
$ips = @('140.82.113.3','140.82.114.3','140.82.112.3','140.82.116.3','140.82.121.3','20.27.177.113')
Write-Output ("MT download artifact $ArtifactId -> $zipPath (race $($ips.Count) IPs)")

$jobs = @()
foreach ($ip in $ips) {
    $jobs += Start-Job -Name "dl_$ip" -ArgumentList $ip, $ArtifactId, $tok, $zipPath -ScriptBlock {
        param($ip, $aid, $tok, $zpath)
        $hh = @{ Authorization = "Bearer $tok"; 'User-Agent' = 'dy-mt' }
        # resolve api.github.com to this IP via hosts-free TcpClient is complex; use --resolve via curl.exe if present
        $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
        if ($curl) {
            & $curl.Source -s --connect-timeout 20 --max-time 90 -L `
                --resolve "api.github.com:443:${ip}:443" `
                -H "Authorization: Bearer $tok" -H "User-Agent: dy-mt" `
                -o $zpath "https://api.github.com/repos/Pupildan/dy-tvos/actions/artifacts/$aid/zip"
            if ($LASTEXITCODE -eq 0 -and (Test-Path $zpath) -and ((Get-Item $zpath).Length -gt 10000)) { return "OK $ip" }
            return "FAIL $ip"
        }
        # fallback: plain Invoke-WebRequest (no --resolve, uses DNS)
        try {
            Invoke-WebRequest -Uri ("https://api.github.com/repos/Pupildan/dy-tvos/actions/artifacts/$aid/zip") -Headers $hh -OutFile $zpath -TimeoutSec 60
            return "OK dns"
        } catch { return "FAIL dns" }
    }
}

# wait for first OK
$winner = $null
$deadline = (Get-Date).AddSeconds(120)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500
    foreach ($j in $jobs) {
        if ($j.State -eq 'Completed') {
            $r = Receive-Job $j
            if ($r -match '^OK') { $winner = $r; break }
        }
    }
    if ($winner) { break }
}
$jobs | Stop-Job -ErrorAction SilentlyContinue
$jobs | Remove-Job -Force -ErrorAction SilentlyContinue

if (-not $winner) { Write-Output 'MT DOWNLOAD FAILED (no IP finished)'; exit 1 }
Write-Output ("winner: $winner")

if (-not (Test-Path $zipPath) -or ((Get-Item $zipPath).Length -lt 10000)) { Write-Output 'zip missing/too small'; exit 1 }
Write-Output ("downloaded zip -> $zipPath (" + [int]((Get-Item $zipPath).Length/1MB) + " MB)")

Add-Type -AssemblyName System.IO.Compression.FileSystem
try {
    Expand-Archive -Path $zipPath -DestinationPath $unpack -Force
    $inner = Get-ChildItem $unpack -Recurse -Filter *.ipa | Select-Object -First 1
    if ($inner) { Copy-Item $inner.FullName (Join-Path $outDir $IpaName) -Force; Write-Output ("IPA -> " + (Join-Path $outDir $IpaName)) }
    else { Write-Output 'no ipa inside artifact'; exit 1 }
} catch {
    Write-Output ("unpack fail: " + $_.Exception.Message); exit 1
}
