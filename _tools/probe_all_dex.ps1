$ErrorActionPreference = 'Continue'
$files = @('classes.dex','classes2.dex','classes3.dex')
foreach ($f in $files) {
    $p = 'C:\Nbeetok\_apk_work\extracted\' + $f
    $bytes = [System.IO.File]::ReadAllBytes($p)
    $s = [Text.Encoding]::ASCII.GetString($bytes)
    Write-Output ("########## " + $f + " (len=" + $s.Length + ") ##########")
    foreach ($kw in @('aweme/v2/feed','snssdk','amemv','mobile_feed','mobile v2/feed','tab/feed','max_cursor','has_more','refresh_index','presented_ids','awemePcRecRawData')) {
        $i = $s.IndexOf($kw)
        if ($i -ge 0) { Write-Output ("  HIT: " + $kw + " @" + $i) }
        else { Write-Output ("  miss: " + $kw) }
    }
}
