@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
if not defined PORT (
  set "PORT=8088"
  set "AUTO_PORT=1"
)

if not exist "%SCRIPT_DIR%site\index.html" (
  echo [ERROR] File site\index.html tidak ditemukan.
  echo Salin seluruh folder contoh-cloudflare, termasuk folder site.
  pause
  exit /b 1
)

where powershell.exe >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Windows PowerShell tidak tersedia di komputer ini.
  pause
  exit /b 1
)

if defined AUTO_PORT (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%serve-local.ps1" -SiteRoot "%SCRIPT_DIR%site" -Port "%PORT%" -AutoPort
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%serve-local.ps1" -SiteRoot "%SCRIPT_DIR%site" -Port "%PORT%"
)
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" pause
exit /b %RESULT%
