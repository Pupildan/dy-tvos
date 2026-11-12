$log = 'C:\Nbeetok\dy-tvos\_tmp\cilog\v44.log'
Select-String -Path $log -Pattern 'Assets.car' | Select-Object -First 5 | ForEach-Object { Write-Output $_.Line }
Write-Output '=== actool compile output segment ==='
$i = ($c = Get-Content $log -Raw).IndexOf('builtin-compileAssetCatalog')
if ($i -lt 0) { $i = $c.IndexOf('actool /Users/runner') }
if ($i -ge 0) {
    $len = [Math]::Min(1600, $c.Length - $i)
    Write-Output $c.Substring($i, $len)
} else {
    Write-Output 'actool invocation not found'
}
