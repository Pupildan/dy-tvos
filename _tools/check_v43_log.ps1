$c = Get-Content 'C:\Nbeetok\dy-tvos\_tmp\cilog\v43.log' -Raw
$i = $c.IndexOf('com.apple.actool.notices')
if ($i -ge 0) {
    $len = [Math]::Min(900, $c.Length - $i)
    Write-Output $c.Substring($i, $len)
} else {
    Write-Output 'no notices section'
}
Write-Output '=== Assets.car mentions ==='
Select-String -Path 'C:\Nbeetok\dy-tvos\_tmp\cilog\v43.log' -Pattern 'Assets.car|CpResource|Copy.*\.car' | Select-Object -First 6 | ForEach-Object { Write-Output $_.Line }
