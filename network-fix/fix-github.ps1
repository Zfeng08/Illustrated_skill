# Auto-find a working GitHub IP and pin it into hosts.
# Run via fix-github.cmd (self-elevating).

param([switch]$NoPause)

$ErrorActionPreference = 'Continue'
$hostsPath = 'C:\Windows\System32\drivers\etc\hosts'
$base      = 'C:\Users\10625\Desktop\Illustrated_skill\network-fix'
$stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup    = Join-Path $base "backup-$stamp"

New-Item -ItemType Directory -Force -Path $backup | Out-Null

Start-Transcript -Path (Join-Path $base 'fix-github.log') -Force | Out-Null

Write-Host "== Scanning GitHub IPs ==" -ForegroundColor Cyan

$candidates = @(
  '140.82.112.3','140.82.112.4','140.82.113.3','140.82.113.4',
  '140.82.114.3','140.82.114.4','140.82.116.3','140.82.121.3',
  '140.82.121.4','20.27.177.113','20.200.245.247','20.205.243.166',
  '20.233.83.145','20.247.166.64','20.247.166.65','20.6.7.17'
)

$good = @()
foreach ($ip in $candidates) {
  $out = (& curl.exe -sS --resolve "github.com:443:$ip" -o NUL `
          -w "%{http_code}|%{time_total}" --max-time 3 `
          -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0" `
          "https://github.com/login" 2>&1) -join ' '
  if ($out -match '^200\|([0-9.]+)') {
    $t = [double]$Matches[1]
    Write-Host ("  OK    {0,-16} {1:N2}s" -f $ip, $t) -ForegroundColor Green
    $good += [pscustomobject]@{ IP = $ip; Time = $t }
  } else {
    Write-Host ("  --    {0,-16} unreachable" -f $ip) -ForegroundColor DarkGray
  }
}

if ($good.Count -eq 0) {
  Write-Host ""
  Write-Host "No reachable GitHub IP right now." -ForegroundColor Red
  Write-Host "GitHub is being blocked on this network at the moment."
  Write-Host "Options: run open-WARP.cmd, or retry in a minute."
  if (-not $NoPause) { Read-Host "Press Enter to exit" }
  exit 1
}

$best = ($good | Sort-Object Time | Select-Object -First 1)
Write-Host ""
Write-Host ("Selected: {0}  ({1:N2}s)" -f $best.IP, $best.Time) -ForegroundColor Yellow

# backup hosts
Copy-Item $hostsPath "$backup\hosts.bak" -Force

# rewrite: drop any existing github.com lines (commented or active), then append pin
$content = Get-Content $hostsPath | Where-Object { $_ -notmatch 'github\.com' }
$content += ""
$content += "# GitHub pin - generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') by fix-github"
$content += "$($best.IP) github.com"
$content += "$($best.IP) www.github.com"
$content | Set-Content $hostsPath -Encoding ASCII

ipconfig /flushdns | Out-Null

Write-Host ""
Write-Host "hosts updated + DNS cache flushed. Verifying..." -ForegroundColor Cyan
Start-Sleep -Seconds 1

$verify = (& curl.exe -sS -o NUL -w "%{http_code}|%{time_total}" --max-time 8 `
           -A "Mozilla/5.0" "https://github.com/login" 2>&1) -join ' '
Write-Host ("  github.com/login -> {0}" -f $verify)

if ($verify -match '^200\|') {
  Write-Host ""
  Write-Host "GitHub is working. Open https://github.com in your browser." -ForegroundColor Green
} else {
  Write-Host ""
  Write-Host "Verification failed - IP may already be blocked. Run this again." -ForegroundColor Red
}
Write-Host ""
if (-not $NoPause) { Read-Host "Press Enter to exit" }
Stop-Transcript | Out-Null
