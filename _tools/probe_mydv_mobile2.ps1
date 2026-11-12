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

Ctx 'aweme/v2/feed' 5362218 900 1400
Ctx 'snssdk' 6005509 500 700
