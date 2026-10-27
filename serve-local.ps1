param(
    [Parameter(Mandatory = $true)][string]$SiteRoot,
    [ValidateRange(1, 65535)][int]$Port = 8088,
    [switch]$AutoPort,
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($SiteRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
if (-not [System.IO.File]::Exists([System.IO.Path]::Combine($root, 'index.html'))) {
    Write-Error "File index.html tidak ditemukan di $root"
    exit 1
}

function Send-Response {
    param(
        [System.IO.Stream]$Stream,
        [int]$Status,
        [string]$Reason,
        [string]$ContentType = 'text/plain; charset=utf-8',
        [byte[]]$Body = @(),
        [bool]$HeadOnly = $false
    )
    $headers = "HTTP/1.1 $Status $Reason`r`nContent-Type: $ContentType`r`nContent-Length: $($Body.Length)`r`nConnection: close`r`nX-Content-Type-Options: nosniff`r`n`r`n"
    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($headers)
    $Stream.Write($headerBytes, 0, $headerBytes.Length)
    if (-not $HeadOnly -and $Body.Length -gt 0) {
        $Stream.Write($Body, 0, $Body.Length)
    }
    $Stream.Flush()
}

$mime = @{
    '.html' = 'text/html; charset=utf-8'
    '.htm' = 'text/html; charset=utf-8'
    '.css' = 'text/css; charset=utf-8'
    '.js' = 'text/javascript; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.svg' = 'image/svg+xml'
    '.png' = 'image/png'
    '.jpg' = 'image/jpeg'
    '.jpeg' = 'image/jpeg'
    '.gif' = 'image/gif'
    '.ico' = 'image/x-icon'
    '.webp' = 'image/webp'
    '.woff' = 'font/woff'
    '.woff2' = 'font/woff2'
}

$listener = $null
$firstPort = $Port
$lastPort = if ($AutoPort) { [Math]::Min(65535, $Port + 12) } else { $Port }
$lastError = $null
for ($candidate = $firstPort; $candidate -le $lastPort; $candidate++) {
    $testListener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $candidate)
    try {
        $testListener.Start()
        $listener = $testListener
        $Port = $candidate
        break
    } catch {
        $lastError = $_
        $testListener.Stop()
    }
}
if ($null -eq $listener) {
    Write-Error "Server gagal dimulai pada port $firstPort sampai $lastPort. Port mungkin sedang dipakai. Detail: $lastError"
    exit 1
}

$url = "http://localhost:$Port/"
$pidDir = Join-Path $PSScriptRoot '.server-pids'
[System.IO.Directory]::CreateDirectory($pidDir) | Out-Null
$pidFile = Join-Path $pidDir "$PID.json"
$processStart = (Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks
@{ pid = $PID; startTicks = $processStart; port = $Port } | ConvertTo-Json -Compress | Set-Content -LiteralPath $pidFile -Encoding UTF8

if ($Port -ne $firstPort) { Write-Host "Port $firstPort sudah dipakai; memakai port $Port." }
Write-Host "Server HTML berjalan: $url"
Write-Host "Folder web: $root"
Write-Host "Untuk Quick Tunnel, gunakan: cloudflared.exe tunnel --url http://127.0.0.1:$Port"
Write-Host 'Biarkan jendela ini terbuka. Tekan Ctrl+C untuk berhenti.'
if (-not $NoBrowser) {
    try { Start-Process $url } catch { Write-Warning "Browser tidak terbuka otomatis; buka $url sendiri." }
}

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $client.ReceiveTimeout = 5000
            $client.SendTimeout = 5000
            $stream = $client.GetStream()
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII, $false, 1024, $true)
            $requestLine = $reader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($requestLine) -or $requestLine.Length -gt 8192) {
                Send-Response -Stream $stream -Status 400 -Reason 'Bad Request'
                continue
            }

            $parts = $requestLine.Split(' ')
            if ($parts.Length -lt 3) {
                Send-Response -Stream $stream -Status 400 -Reason 'Bad Request'
                continue
            }
            $method = $parts[0]
            $target = $parts[1]
            $headerCount = 0
            do {
                $line = $reader.ReadLine()
                $headerCount++
            } while ($null -ne $line -and $line.Length -gt 0 -and $headerCount -lt 100 -and $line.Length -le 8192)
            if ($null -ne $line -and ($headerCount -ge 100 -or $line.Length -gt 8192)) {
                Send-Response -Stream $stream -Status 431 -Reason 'Request Header Fields Too Large'
                continue
            }
            if ($method -notin @('GET', 'HEAD')) {
                Send-Response -Stream $stream -Status 405 -Reason 'Method Not Allowed'
                continue
            }
            if (-not $target.StartsWith('/')) {
                Send-Response -Stream $stream -Status 400 -Reason 'Bad Request'
                continue
            }

            $pathPart = $target.Split('?')[0]
            $relative = [System.Uri]::UnescapeDataString($pathPart).TrimStart('/')
            if ([string]::IsNullOrWhiteSpace($relative)) { $relative = 'index.html' }
            $relative = $relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
            $file = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($root, $relative))
            $insideRoot = $file.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
            if (-not $insideRoot) {
                Send-Response -Stream $stream -Status 403 -Reason 'Forbidden'
                continue
            }
            if ([System.IO.Directory]::Exists($file)) { $file = [System.IO.Path]::Combine($file, 'index.html') }
            if (-not [System.IO.File]::Exists($file)) {
                Send-Response -Stream $stream -Status 404 -Reason 'Not Found'
                continue
            }

            $extension = [System.IO.Path]::GetExtension($file).ToLowerInvariant()
            $contentType = if ($mime.ContainsKey($extension)) { $mime[$extension] } else { 'application/octet-stream' }
            $bytes = [System.IO.File]::ReadAllBytes($file)
            Send-Response -Stream $stream -Status 200 -Reason 'OK' -ContentType $contentType -Body $bytes -HeadOnly ($method -eq 'HEAD')
        } catch {
            Write-Warning "Permintaan gagal: $_"
        } finally {
            $client.Close()
        }
    }
} finally {
    $listener.Stop()
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
}
