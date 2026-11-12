# DY pipeline shared helpers: lock-free hosts writer + API/git host rotation
$ErrorActionPreference = 'Continue'
$script:hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$script:GH_IPS = @('140.82.113.3','140.82.114.3','140.82.112.3','140.82.116.3','140.82.121.3','20.27.177.113')

function Set-HostIp([string]$hostname, [string]$ip) {
    # Lock-free rewrite via FileStream to avoid Set-Content "Stream was not readable"
    $lines = [System.IO.File]::ReadAllLines($script:hostsPath)
    $pattern = '^\s*\S+\s+' + [regex]::Escape($hostname) + '\s*$'
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($l in $lines) {
        if ($l -match $pattern) { $out.Add("$ip $hostname") } else { $out.Add($l) }
    }
    if (-not ($out -match $pattern)) { $out.Add("$ip $hostname") }
    $fs = [System.IO.File]::Open($script:hostsPath, 'Create', 'Write', 'ReadWrite')
    try {
        $sw = New-Object System.IO.StreamWriter($fs, (New-Object System.Text.ASCIIEncoding))
        foreach ($l in $out) { $sw.WriteLine($l) }
        $sw.Flush()
    } finally { $fs.Close() }
    ipconfig /flushdns | Out-Null
}

function Resolve-GhHost([string]$hostname, [string[]]$ips) {
    foreach ($ip in $ips) {
        try { Set-HostIp $hostname $ip } catch { Write-Output ("  hosts write warn: " + $_.Exception.Message) }
        return $ip
    }
    return $null
}
