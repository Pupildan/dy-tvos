$ErrorActionPreference = 'Stop'
$src = [System.IO.File]::ReadAllText('C:\Nbeetok\dy-tvos\App\Sources\App\DYWebViewShim.m')
$i = $src.IndexOf('DYFetchHookJS =')
$j = $src.IndexOf('void DYInstallFetchHook')
if ($i -lt 0 -or $j -lt 0) { Write-Output 'MARKERS NOT FOUND'; exit 1 }
$block = $src.Substring($i, $j - $i)

# 提取每个 @"..." 片段的内容并按 ObjC 规则拼接（相邻字面量直接相连，无分隔符）
$parts = New-Object System.Collections.Generic.List[string]
$lines = $block -split "`r?`n"
foreach ($line in $lines) {
    if ($line -match '@"(.*)"\s*$') {
        $content = $Matches[1]
        # ObjC 转义链：源码 -> C 字符串。\\\\(4)->\\(C级2)，\\(2)->\(C级1)，\"->"
        $content = $content.Replace('\\\\', "`u0001`u0001")
        $content = $content.Replace('\\"', "`u0002")
        $content = $content.Replace('\\', "`u0003")
        $content = $content.Replace("`u0001`u0001", '\\')
        $content = $content.Replace("`u0002", '"')
        $content = $content.Replace("`u0003", '\')
        $parts.Add($content)
    }
}
$js = $parts -join ''
[System.IO.File]::WriteAllText('C:\Nbeetok\dy-tvos\_tmp\hook_extracted.js', $js)
Write-Output ('extracted chars=' + $js.Length)
Write-Output ('first 80: ' + $js.Substring(0, [Math]::Min(80, $js.Length)))
