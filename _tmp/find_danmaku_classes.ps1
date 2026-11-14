$dir = 'C:\Nbeetok\_apk_work\jadx_out_classes\sources\defpackage'
Get-ChildItem $dir -Filter '*.java' | Select-String -Pattern 'DanmakuItem|DanmakuResponse|danmaku' -List | Select-Object -First 20 Filename,LineNumber
