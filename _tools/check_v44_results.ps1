$log = 'C:\Nbeetok\dy-tvos\_tmp\cilog\v44.log'
$c = Get-Content $log -Raw
# 找第一个 compilation-results 标记，取其后 500 字符
$idx = $c.IndexOf('com.apple.actool.compilation-results')
if ($idx -ge 0) {
    $len = [Math]::Min(500, $c.Length - $idx)
    Write-Output $c.Substring($idx, $len)
} else {
    Write-Output 'marker not found'
}
