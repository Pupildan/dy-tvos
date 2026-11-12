$log = 'C:\Nbeetok\dy-tvos\_tmp\cilog\v44.log'
$c = Get-Content $log -Raw
$i = $c.IndexOf('com.apple.actool.notices')
if ($i -ge 0) {
    $len = [Math]::Min(800, $c.Length - $i)
    Write-Output '=== notices ==='
    Write-Output $c.Substring($i, $len)
}
Write-Output '=== doc warnings ==='
$j = $c.IndexOf('com.apple.actool.document.warnings')
if ($j -ge 0) {
    $len2 = [Math]::Min(700, $c.Length - $j)
    Write-Output $c.Substring($j, $len2)
}
Write-Output '=== brand/appicon mentions ==='
Select-String -Path $log -Pattern 'brand|AppIcon.brandassets|unassigned' | Select-Object -First 6 | ForEach-Object { Write-Output $_.Line }
