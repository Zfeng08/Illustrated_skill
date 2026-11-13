# Restore WARP ON, remove GitHub hosts pins so WARP's tunnel handles GitHub.
param([switch]$NoPause)

$ErrorActionPreference = 'Continue'
$hostsPath = 'C:\Windows\System32\drivers\etc\hosts'
$base      = 'C:\Users\10625\Desktop\Illustrated_skill\network-fix'
$stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup    = Join-Path $base "backup-$stamp"
$warpCli   = 'C:\Program Files\Cloudflare\Cloudflare WARP\warp-cli.exe'

New-Item -ItemType Directory -Force -Path $backup | Out-Null
Start-Transcript -Path (Join-Path $base 'restore-github.log') -Force | Out-Null

Write-Host "[1/5] Removing GitHub hosts pins..." -ForegroundColor Cyan
Copy-Item $hostsPath "$backup\hosts.bak" -Force
$content = Get-Content $hostsPath | Where-Object {
  $_ -notmatch 'github\.com' -and $_ -notmatch 'githubusercontent\.com'
}
$content | Set-Content $hostsPath -Encoding ASCII

Write-Host "[2/5] Starting WARP service..." -ForegroundColor Cyan
sc.exe config CloudflareWARP start= auto | Out-Null
net start CloudflareWARP 2>&1 | Out-Null
Start-Sleep -Seconds 3

Write-Host "[3/5] Connecting tunnel..." -ForegroundColor Cyan
& $warpCli connect 2>&1 | ForEach-Object { "      $_" }

# wait for connected
$deadline = (Get-Date).AddSeconds(45)
$state = ''
while ((Get-Date) -lt $deadline) {
  $s = (& $warpCli status 2>&1) -join ' '
  if ($s -match 'Connected') { $state = 'Connected'; break }
  Start-Sleep -Seconds 2
}
Write-Host ("      warp status: " + (& $warpCli status 2>&1) -join ' ')

Write-Host "[4/5] Flushing DNS..." -ForegroundColor Cyan
ipconfig /flushdns | Out-Null
Start-Sleep -Seconds 2

Write-Host "[5/5] Verifying..." -ForegroundColor Cyan
$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131.0'
$targets = @(
  @{ H='github.com';                P='/login' },
  @{ H='api.github.com';            P='/rate_limit' },
  @{ H='raw.githubusercontent.com'; P='/github/gitignore/main/README.md' },
  @{ H='www.cloudflare.com';        P='/' },
  @{ H='www.baidu.com';             P='/' }
)
foreach ($t in $targets) {
  $out = (& curl.exe -sS -o NUL -w "%{http_code}|%{time_total}" --max-time 20 -A $UA "https://$($t.H)$($t.P)" 2>&1) -join ' '
  Write-Host ("      {0,-32} {1}" -f $t.H, $out)
}

Write-Host ""
Write-Host "Tunnel routes now: " -NoNewline
$r = @(route print -4 | Select-String '192\.0\.2\.1').Count
Write-Host $r
Write-Host ""
Write-Host "Done. GitHub should work through WARP now." -ForegroundColor Green
Write-Host "Note: Cloudflare-CDN sites carry ~215ms + packet loss while WARP is on."
if (-not $NoPause) { Read-Host "Press Enter to exit" }
Stop-Transcript | Out-Null
