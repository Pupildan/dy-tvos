$ErrorActionPreference = 'Continue'
$p = 'C:\Nbeetok\_apk_work\extracted\classes2.dex'
$bytes = [System.IO.File]::ReadAllBytes($p)
$s = [Text.Encoding]::ASCII.GetString($bytes)

function Ctx([string]$label, [int]$pos, [int]$before, [int]$after) {
    $st = [Math]::Max(0, $pos - $before)
    $len = [Math]::Min($before + $after, $s.Length - $st)
    $seg = $s.Substring($st, $len) -replace '[^\x20-\x7E]', '.'
    Write-Output ("=== $label @$pos ===")
    Write-Output $seg
    Write-Output ''
}

foreach ($kw in @('max_time','device/register','aid=1128','openudid','client_version','device_id=','iid=','v2/feed/?')) {
    $i = $s.IndexOf($kw)
    if ($i -ge 0) { Ctx $kw $i 400 600 } else { Write-Output "=== $kw NOT FOUND ==="; Write-Output '' }
}
