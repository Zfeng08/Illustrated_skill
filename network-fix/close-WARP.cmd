@echo off
chcp 65001 >nul
setlocal
net session >nul 2>&1
if %errorlevel% neq 0 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

echo ============================================
echo   Turn WARP OFF  (full-speed direct mode)
echo ============================================
echo.

echo [1/5] Disconnecting tunnel...
"C:\Program Files\Cloudflare\Cloudflare WARP\warp-cli.exe" disconnect >nul 2>&1
timeout /t 2 /nobreak >nul

echo [2/5] Stopping service + disabling auto-start...
sc stop CloudflareWARP >nul 2>&1
sc config CloudflareWARP start= demand >nul 2>&1
timeout /t 2 /nobreak >nul

echo [3/5] Restoring domestic DNS (223.5.5.5 / 119.29.29.29)...
netsh interface ipv4 set dnsservers name="WLAN" source=static address=223.5.5.5 register=primary >nul
netsh interface ipv4 add dnsservers name="WLAN" address=119.29.29.29 index=2 >nul

echo [4/5] Flushing DNS cache...
ipconfig /flushdns >nul

echo [5/5] Checking tunnel routes (empty = clean)...
route print -4 | findstr "192.0.2.1"

echo.
echo Done. Default route:
route print -4 | findstr "0.0.0.0          0.0.0.0"
echo.
pause
