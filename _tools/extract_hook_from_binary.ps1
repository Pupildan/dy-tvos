$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z = [System.IO.Compression.ZipFile]::OpenRead('C:\Nbeetok\dy-tvos\output\DYTV-tvos-unsigned-v46.ipa')
$e = $z.Entries | Where-Object { $_.FullName -eq 'Payload/DYTV.app/DYTV' }
$s = $e.Open()
$ms = New-Object IO.MemoryStream
$s.CopyTo($ms)
$z.Dispose()
$b = $ms.ToArray()
# 在二进制里找 HOOK_START，向前找 "(function(){"，向后找 "})();"
$text = [Text.Encoding]::ASCII.GetString($b)
$k = $text.IndexOf('HOOK_START')
Write-Output ("HOOK_START @ " + $k)
$start = $text.LastIndexOf('(function(){', $k)
$endMarker = $text.IndexOf('HOOK_INSTALLED'); 
# hook 结尾是 post('HOOK_INSTALLED');...post('COOKIE...})();  找 COOKIE 之后的 })();
$ck = $text.IndexOf('try{ post(', $k)
$end = $text.IndexOf('})();', $ck)
$len = $end - $start + 5
Write-Output ("span " + $start + " .. " + $end + " len=" + $len)
$js = $text.Substring($start, $len)
# 二进制里 C 字符串以 0x00 结尾，中间不应有 0x00；去掉可能的杂散控制符
$js = ($js.ToCharArray() | Where-Object { [int]$_ -ge 32 -or [int]$_ -eq 10 }) -join ''
[System.IO.File]::WriteAllText('C:\Nbeetok\dy-tvos\_tmp\hook_from_binary.js', $js)
Write-Output ('chars=' + $js.Length)
