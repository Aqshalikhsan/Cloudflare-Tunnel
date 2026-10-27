$ErrorActionPreference = 'Stop'
$pidDir = Join-Path $PSScriptRoot '.server-pids'

$stopped = 0
if ([System.IO.Directory]::Exists($pidDir)) {
    Get-ChildItem -LiteralPath $pidDir -Filter '*.json' -File | ForEach-Object {
        $pidFile = $_.FullName
        try {
            $record = Get-Content -LiteralPath $pidFile -Raw | ConvertFrom-Json
            $serverProcess = Get-Process -Id ([int]$record.pid) -ErrorAction SilentlyContinue
            if ($null -ne $serverProcess -and $serverProcess.StartTime.ToUniversalTime().Ticks -eq [long]$record.startTicks) {
                Stop-Process -Id $serverProcess.Id -ErrorAction Stop
                Write-Host "Server port $($record.port) dihentikan (PID $($record.pid))."
                $stopped++
            }
        } catch {
            Write-Warning "Gagal memeriksa $pidFile : $_"
        } finally {
            Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
        }
    }
}

# Hentikan juga contoh Python http.server yang menyajikan folder site materi ini.
$knownSites = @([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'site')))
$siblingSite = Join-Path (Split-Path $PSScriptRoot -Parent) 'contoh-cloudflare\site'
if ([System.IO.Directory]::Exists($siblingSite)) {
    $knownSites += [System.IO.Path]::GetFullPath($siblingSite)
}
$pythonServers = Get-CimInstance Win32_Process -Filter "Name = 'python.exe' OR Name = 'pythonw.exe'" -ErrorAction SilentlyContinue
foreach ($server in $pythonServers) {
    $line = [string]$server.CommandLine
    if ($line -notmatch '(?i)(?:^|\s)-m\s+http\.server(?:\s|$)') { continue }
    $matchesSite = $false
    foreach ($site in $knownSites) {
        if ($line.IndexOf($site, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $matchesSite = $true
            break
        }
    }
    if (-not $matchesSite) { continue }
    try {
        Stop-Process -Id $server.ProcessId -ErrorAction Stop
        Write-Host "Server Python contoh dihentikan (PID $($server.ProcessId))."
        $stopped++
    } catch {
        Write-Warning "Gagal menghentikan Python PID $($server.ProcessId): $_"
    }
}
if ($stopped -eq 0) { Write-Host 'Tidak ada server latihan dari folder materi ini yang sedang berjalan.' }
