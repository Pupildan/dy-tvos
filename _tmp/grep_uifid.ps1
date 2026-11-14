$dir = 'C:\Nbeetok\_apk_work\jadx_out_classes\sources\defpackage'
Get-ChildItem $dir -Filter '*.java' | Select-String -Pattern 'UIFID_TEMP' -List | Select-Object -First 8 Filename,LineNumber
Select-String -Path (Join-Path $dir 'sl4.java') -Pattern 'UIFID' | Select-Object -First 10 LineNumber,Line
