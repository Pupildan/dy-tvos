# DY log collector (dev machine): RAW TCP line listener -> appends ATV-pushed lines to a file.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File dy_collector.ps1
# ATV opens TCP to <dev-ip>:9988 and writes "<text>\n" per log line. No HTTP/ATS involved.
$ErrorActionPreference = 'Continue'
$port = 9988
$outFile = 'C:\Nbeetok\dy-tvos\output\atv_push.log'
New-Item -ItemType Directory -Force -Path (Split-Path $outFile) | Out-Null
"=== collector started $(Get-Date -Format HH:mm:ss) ===" | Out-File $outFile -Encoding utf8

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $port)
$listener.Start()
Write-Output "collector(TCP) listening on :$port -> $outFile"

while ($true) {
    try {
        $client = $listener.AcceptTcpClient()
        $stream = $client.GetStream()
        $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8)
        while ($null -ne ($line = $reader.ReadLine())) {
            if ($line.Length -gt 0) {
                "$(Get-Date -Format HH:mm:ss)  $line" | Out-File $outFile -Append -Encoding utf8
            }
        }
        $client.Close()
    } catch {
        Write-Output "loop err: $_"
        Start-Sleep -Milliseconds 200
    }
}
