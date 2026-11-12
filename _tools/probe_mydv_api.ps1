$ErrorActionPreference = 'Continue'
$p = 'C:\Nbeetok\_apk_work\extracted\classes.dex'
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

# 1) tab/feed endpoint
$i = $s.IndexOf('tab/feed')
if ($i -ge 0) { Ctx 'tab/feed' $i 400 500 }

# 2) DouyinDirectApi class context
$i = $s.IndexOf('DouyinDirectApi')
if ($i -ge 0) { Ctx 'DouyinDirectApi' $i 300 700 }

# 3) generateABogusParam
$i = $s.IndexOf('generateABogusParam')
if ($i -ge 0) { Ctx 'generateABogusParam' $i 500 500 }

# 4) device_id
$i = $s.IndexOf('device_id')
if ($i -ge 0) { Ctx 'device_id' $i 400 400 }

# 5) webid registration
$i = $s.IndexOf('webid')
if ($i -ge 0) { Ctx 'webid' $i 300 400 }
