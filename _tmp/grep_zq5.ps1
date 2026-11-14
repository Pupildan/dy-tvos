$dir = 'C:\Nbeetok\_apk_work\jadx_out_classes\sources\defpackage'
Get-ChildItem $dir -Filter '*.java' | Select-String -Pattern 'zq5' -List | Select-Object -First 12 Filename,LineNumber
