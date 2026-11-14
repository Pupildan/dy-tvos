$dir = 'C:\Nbeetok\_apk_work\jadx_out_classes\sources\defpackage'
Get-ChildItem $dir -Filter '*.java' | Select-String -Pattern 'getDanmakuList|DanmakuResponse' -List | Select-Object -First 10 Filename,LineNumber
