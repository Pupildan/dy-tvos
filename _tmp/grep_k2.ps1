$dir = 'C:\Nbeetok\_apk_work\jadx_out_classes\sources\defpackage'
foreach ($f in @('rn5.java','m.java','tw0.java')) {
    Write-Output ('=== ' + $f + ' ===')
    Select-String -Path (Join-Path $dir $f) -Pattern '\.K\(' | Select-Object -First 4 LineNumber,Line
}
