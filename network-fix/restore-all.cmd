@echo off
chcp 65001 >nul
setlocal
net session >nul 2>&1
if %errorlevel% neq 0 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

set BACKUP=%~dp0backup-20261113-150231

echo ============================================
echo   RESTORE original settings
echo ============================================
echo.

if not exist "%BACKUP%\hosts.bak" (
  echo ERROR: backup not found at "%BACKUP%"
  pause
  exit /b 1
)

echo [1/4] Restoring hosts file...
copy /Y "%BACKUP%\hosts.bak" "C:\Windows\System32\drivers\etc\hosts" >nul
echo       hosts restored

echo [2/4] Restoring DNS to DHCP...
netsh interface ipv4 set dnsservers name="WLAN" source=dhcp >nul
echo       DNS -> automatic

echo [3/4] Restoring WARP service to auto-start...
sc config CloudflareWARP start= auto >nul 2>&1
net start CloudflareWARP >nul 2>&1
timeout /t 4 /nobreak >nul

echo [4/4] Flushing DNS cache...
ipconfig /flushdns >nul

echo.
echo Restored. WARP status:
"C:\Program Files\Cloudflare\Cloudflare WARP\warp-cli.exe" status
echo.
echo NOTE: WARP will re-inject its own DNS (127.0.2.2) once connected.
pause
