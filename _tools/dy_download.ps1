# DY: download a single artifact by id into output\ (retry with IP rotation)
param(
    [Parameter(Mandatory=$true)][string]$ArtifactId,
    [Parameter(Mandatory=$true)][string]$IpaName
)
$ErrorActionPreference = 'Continue'
. 'C:\Nbeetok\dy-tvos\_tools\dy_common.ps1'
$cfg = Get-Content 'C:\Users\Admin\WorkBuddy\fndanmu-tvos\build-package\swiftfin-fnos\.git\config' -Raw
if ($cfg -match 'x-access-token:([^@]+)@') { $tok = $Matches[1].Trim() } else { throw 'no token' }
$outDir = 'C:\Nbeetok\dy-tvos\output'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$h = @{ Authorization = "Bearer $tok"; 'User-Agent'='dy-pipeline' }
$zipPath = Join-Path $outDir "$IpaName.zip"

$done = $false
for ($i = 0; $i -lt $script:GH_IPS.Count -and -not $done; $i++) {
    $ip = Resolve-GhHost 'api.github.com' $script:GH_IPS
    try {
        Write-Output ("download try via " + $ip)
        Invoke-WebRequest -Uri ("https://api.github.com/repos/Pupildan/dy-tvos/actions/artifacts/{0}/zip" -f $ArtifactId) -Headers $h -OutFile $zipPath -TimeoutSec 120
        $done = $true
    } catch { Write-Output ("  fail: " + $_.Exception.Message) }
}
if (-not $done) { Write-Output 'DOWNLOAD FAILED'; exit 1 }

$unpack = Join-Path $outDir '_unpack'
Expand-Archive -Path $zipPath -DestinationPath $unpack -Force
$inner = Get-ChildItem $unpack -Recurse -Filter *.ipa | Select-Object -First 1
if ($inner) { Copy-Item $inner.FullName (Join-Path $outDir $IpaName) -Force; Write-Output ("IPA -> " + (Join-Path $outDir $IpaName)) }
else {
    $anyZip = Get-ChildItem $unpack -Recurse -Filter *.zip | Select-Object -First 1
    if ($anyZip) { Copy-Item $anyZip.FullName (Join-Path $outDir $IpaName) -Force; Write-Output ("IPA(zip) -> " + (Join-Path $outDir $IpaName)) }
    else { Write-Output 'no ipa inside artifact'; exit 1 }
}
Remove-Item $unpack -Recurse -Force -ErrorAction SilentlyContinue
Write-Output 'RESULT download_done'
