$dir = 'C:\Nbeetok\_apk_work\jadx_out_classes\sources\defpackage'
Get-ChildItem $dir -Filter '*.java' | Select-String -Pattern '\.K\(' -List | Select-Object -First 8 Filename,LineNumber
