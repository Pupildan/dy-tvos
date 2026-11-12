# DY one-shot pipeline: commit -> push -> watch CI -> download unsigned ipa into workspace
param(
    [string]$Version = 'v1',
    [string]$CommitMsg = ''
)
$ErrorActionPreference = 'Continue'
. 'C:\Nbeetok\dy-tvos\_tools\dy_common.ps1'

$repo   = 'C:\Nbeetok\dy-tvos'
$git    = 'C:\Users\Admin\WorkBuddy\fndanmu-tvos\_tools\MinGit\cmd\git.exe'
$outDir = 'C:\Nbeetok\dy-tvos\output'
$ipaName = "DYTV-tvos-unsigned-$Version.ipa"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$cfg = Get-Content 'C:\Users\Admin\WorkBuddy\fndanmu-tvos\build-package\swiftfin-fnos\.git\config' -Raw
if ($cfg -match 'x-access-token:([^@]+)@') { $tok = $Matches[1].Trim() } else { throw 'no token' }
$h = @{ Authorization = "Bearer $tok"; Accept = 'application/vnd.github+json'; 'User-Agent' = 'dy-pipeline' }

# --- 1) git init + remote + commit ---
if (-not (Test-Path "$repo\.git")) {
    & $git -C $repo init | Out-Null
    & $git -C $repo branch -M main | Out-Null
}
$remoteUrl = "https://x-access-token:$tok@github.com/Pupildan/dy-tvos.git"
$existing = & $git -C $repo remote | Where-Object { $_ -eq 'origin' }
if ($existing) { & $git -C $repo remote set-url origin $remoteUrl | Out-Null }
else { & $git -C $repo remote add origin $remoteUrl | Out-Null }

& $git -C $repo add -A | Out-Null
if (-not $CommitMsg) { $CommitMsg = "$Version`: pipeline push" }
$hasChanges = (& $git -C $repo status --porcelain)
if ($hasChanges) { & $git -C $repo commit -m $CommitMsg | Out-Null; Write-Output "committed: $CommitMsg" }
else { Write-Output 'nothing to commit' }
$sha = (& $git -C $repo rev-parse HEAD).Substring(0,7)
Write-Output "HEAD sha=$sha"

# --- 2) push with github.com IP rotation ---
$pushed = $false
for ($i = 0; $i -lt $script:GH_IPS.Count; $i++) {
    $ip = Resolve-GhHost 'github.com' $script:GH_IPS
    Write-Output ("[{0}] push attempt via {1}" -f (Get-Date -Format HH:mm:ss), $ip)
    & $git -C $repo push origin main 2>&1 | ForEach-Object { Write-Output "  $_" }
    if ($LASTEXITCODE -eq 0) { Write-Output "PUSHED via $ip"; $pushed = $true; break }
    Start-Sleep -Seconds 15
}
if (-not $pushed) { Write-Output 'GAVE UP push'; exit 1 }

# --- 3) watch CI by sha ---
Write-Output "watching CI for sha=$sha ..."
$run = $null
for ($i = 0; $i -lt 90; $i++) {
    $ip = Resolve-GhHost 'api.github.com' $script:GH_IPS
    try {
        $runs = Invoke-RestMethod -Uri 'https://api.github.com/repos/Pupildan/dy-tvos/actions/runs?per_page=10' -Headers $h -TimeoutSec 20
        $mine = $runs.workflow_runs | Where-Object { $_.head_sha.StartsWith($sha) } | Select-Object -First 1
        if ($mine) {
            $run = $mine
            Write-Output ("[{0}] run={1} status={2} concl={3}" -f (Get-Date -Format HH:mm:ss), $mine.id, $mine.status, $mine.conclusion)
            if ($mine.status -eq 'completed') { break }
        } else {
            Write-Output ("[{0}] run not created yet" -f (Get-Date -Format HH:mm:ss))
        }
    } catch { Write-Output ("  watch poll fail: " + $_.Exception.Message) }
    Start-Sleep -Seconds 10
}
if (-not $run -or $run.status -ne 'completed') { Write-Output 'CI did not complete in time'; exit 1 }
if ($run.conclusion -ne 'success') {
    Write-Output ("CI FAILED (conclusion=" + $run.conclusion + "). fetch errors:")
    & powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Nbeetok\dy-tvos\_tools\dy_fetch_errors.ps1' -RunId $run.id
    exit 1
}

# --- 4) download artifact ---
$ip = Resolve-GhHost 'api.github.com' $script:GH_IPS
$arts = Invoke-RestMethod -Uri ("https://api.github.com/repos/Pupildan/dy-tvos/actions/runs/{0}/artifacts" -f $run.id) -Headers $h -TimeoutSec 20
$art = $arts.artifacts | Where-Object { $_.name -eq 'DYTV-tvos-unsigned' } | Select-Object -First 1
if (-not $art) { Write-Output 'artifact DYTV-tvos-unsigned not found'; exit 1 }
Write-Output ("ARTIFACT id={0} size_mb={1}" -f $art.id, [math]::Round($art.size_in_bytes/1MB,1))

$zipPath = Join-Path $outDir "$ipaName.zip"
$dlHdr = @{ Authorization = "Bearer $tok"; 'User-Agent'='dy-pipeline' }
$ip = Resolve-GhHost 'api.github.com' $script:GH_IPS
Invoke-WebRequest -Uri ("https://api.github.com/repos/Pupildan/dy-tvos/actions/artifacts/{0}/zip" -f $art.id) -Headers $dlHdr -OutFile $zipPath -TimeoutSec 120
Write-Output ("downloaded zip -> " + $zipPath)

# artifact zip contains the .ipa; extract and place ipa in output
Expand-Archive -Path $zipPath -DestinationPath (Join-Path $outDir '_unpack') -Force
$inner = Get-ChildItem (Join-Path $outDir '_unpack') -Recurse -Filter *.ipa | Select-Object -First 1
if ($inner) { Copy-Item $inner.FullName (Join-Path $outDir $ipaName) -Force; Write-Output ("IPA -> " + (Join-Path $outDir $ipaName)) }
else {
    # artifact may be the zip-of-Payload directly; repackage not needed if ipa already named
    $anyZip = Get-ChildItem (Join-Path $outDir '_unpack') -Recurse -Filter *.zip | Select-Object -First 1
    if ($anyZip) { Copy-Item $anyZip.FullName (Join-Path $outDir $ipaName) -Force; Write-Output ("IPA(from zip) -> " + (Join-Path $outDir $ipaName)) }
    else { Write-Output 'no ipa/zip inside artifact'; exit 1 }
}
Remove-Item (Join-Path $outDir '_unpack') -Recurse -Force -ErrorAction SilentlyContinue
Write-Output 'RESULT pipeline_done'
