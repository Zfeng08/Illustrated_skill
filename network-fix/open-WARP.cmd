@echo off
chcp 65001 >nul
setlocal
net session >nul 2>&1
if %errorlevel% neq 0 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

echo ============================================
echo   Turn WARP ON  (for Google / YouTube / X)
echo ============================================
echo.

echo [1/4] Starting Cloudflare WARP service...
sc config CloudflareWARP start= demand >nul 2>&1
net start CloudflareWARP >nul 2>&1
timeout /t 2 /nobreak >nul

echo [2/4] Connecting tunnel...
"C:\Program Files\Cloudflare\Cloudflare WARP\warp-cli.exe" connect
timeout /t 6 /nobreak >nul

echo [3/4] Flushing DNS cache...
ipconfig /flushdns >nul

echo [4/4] Current status:
"C:\Program Files\Cloudflare\Cloudflare WARP\warp-cli.exe" status

echo.
echo WARP is ON.  Google / YouTube / Twitter reachable.
echo WARNING: while ON, Cloudflare-CDN sites gain ~200ms + packet loss.
echo Run "close-WARP" when you are done.
echo.
pause
