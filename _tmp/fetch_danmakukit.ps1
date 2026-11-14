# vendor DanmakuKit (MIT, qyz777) core sources into DYTV via GitHub contents API (base64)
. 'C:\Nbeetok\dy-tvos\_tools\dy_common.ps1'
$files = @(
    'Sources/DanmakuKit/Classes/Core/DanmakuAsyncLayer.swift',
    'Sources/DanmakuKit/Classes/Core/DanmakuCell.swift',
    'Sources/DanmakuKit/Classes/Core/DanmakuCellModel.swift',
    'Sources/DanmakuKit/Classes/Core/DanmakuQueuePool.swift',
    'Sources/DanmakuKit/Classes/Core/DanmakuTrack.swift',
    'Sources/DanmakuKit/Classes/Core/DanmakuView.swift',
    'Sources/DanmakuKit/Classes/Core/PlatformTypes.swift',
    'LICENSE'
)
$destRoot = 'C:\Nbeetok\dy-tvos\App\Sources\DanmakuKit'
New-Item -ItemType Directory -Force -Path $destRoot | Out-Null
foreach ($f in $files) {
    $ip = Resolve-GhHost 'api.github.com' $script:GH_IPS
    try {
        $r = Invoke-RestMethod -Uri ('https://api.github.com/repos/qyz777/DanmakuKit/contents/' + $f + '?ref=master') -Headers @{ 'User-Agent'='dy-pipeline' } -TimeoutSec 25
        $bytes = [Convert]::FromBase64String(($r.content -replace '\s',''))
        if ($f -eq 'LICENSE') { $out = Join-Path $destRoot 'LICENSE-DanmakuKit.txt' } else { $out = Join-Path $destRoot (Split-Path $f -Leaf) }
        [IO.File]::WriteAllBytes($out, $bytes)
        Write-Output ("ok " + $out + "  " + $bytes.Length + "B")
    } catch {
        Write-Output ("FAIL " + $f + " : " + $_.Exception.Message)
    }
}
