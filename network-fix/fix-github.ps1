# Auto-find working GitHub IPs and pin them into hosts.
# Handles: github.com / www.github.com / raw.githubusercontent.com / gist.github.com
# Run via fix-github.cmd (self-elevating), or:
#   powershell -ExecutionPolicy Bypass -File fix-github.ps1 -NoPause

param([switch]$NoPause)

$ErrorActionPreference = 'Continue'
$hostsPath = 'C:\Windows\System32\drivers\etc\hosts'
$base      = 'C:\Users\10625\Desktop\Illustrated_skill\network-fix'
$stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup    = Join-Path $base "backup-$stamp"

New-Item -ItemType Directory -Force -Path $backup | Out-Null
Start-Transcript -Path (Join-Path $base 'fix-github.log') -Force | Out-Null

$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131.0 Safari/537.36'

$ghPool = @(
  '20.27.177.113','20.200.245.247','20.205.243.166','20.233.83.145','20.6.7.17',
  '140.82.112.3','140.82.112.4','140.82.113.3','140.82.113.4',
  '140.82.114.3','140.82.114.4','140.82.116.3','140.82.121.3','140.82.121.4'
)
$rawPool = @('185.199.111.133','185.199.110.133','185.199.109.133','185.199.108.133')

# host -> @{ candidates; testPath }
$targets = [ordered]@{
  'github.com'                = @{ Pool = $ghPool;  Path = '/login' }
  'raw.githubusercontent.com' = @{ Pool = $rawPool; Path = '/github/gitignore/main/README.md' }
  'gist.github.com'           = @{ Pool = $ghPool;  Path = '/' }
}

function Test-Ip {
  param($HostName, $Ip, $Path, $TimeoutSec = 3)
  $url = "https://$HostName$Path"
  $out = (& curl.exe -sS --resolve "${HostName}:443:$Ip" -o NUL `
          -w "%{http_code}|%{time_total}" --max-time $TimeoutSec -A $UA $url 2>&1) -join ' '
  if ($out -match '^(200|30[1278])\|([0-9.]+)') {
    return [pscustomobject]@{ IP = $Ip; Code = $Matches[1]; Time = [double]$Matches[2] }
  }
  return $null
}

$chosen = [ordered]@{}

foreach ($h in $targets.Keys) {
  $cfg = $targets[$h]
  Write-Host ""
  Write-Host "== $h ==" -ForegroundColor Cyan
  $good = @()
  foreach ($ip in $cfg.Pool) {
    $r = Test-Ip -HostName $h -Ip $ip -Path $cfg.Path
    if ($r) {
      Write-Host ("   OK   {0,-16} {1,-4} {2:N2}s" -f $ip, $r.Code, $r.Time) -ForegroundColor Green
      $good += $r
    } else {
      Write-Host ("   --   {0,-16} unreachable" -f $ip) -ForegroundColor DarkGray
    }
  }
  if ($good.Count -gt 0) {
    $best = ($good | Sort-Object Time | Select-Object -First 1)
    $chosen[$h] = $best.IP
    Write-Host ("   => pick {0}  ({1:N2}s)" -f $best.IP, $best.Time) -ForegroundColor Yellow
  } else {
    Write-Host "   => NO WORKING IP (leave DNS as-is)" -ForegroundColor Red
  }
}

if ($chosen.Count -eq 0) {
  Write-Host ""
  Write-Host "Nothing reachable. GitHub is fully blocked right now." -ForegroundColor Red
  Write-Host "Try open-WARP.cmd, or retry later."
  if (-not $NoPause) { Read-Host "Press Enter to exit" }
  Stop-Transcript | Out-Null
  exit 1
}

# --- rewrite hosts ---
Copy-Item $hostsPath "$backup\hosts.bak" -Force

$managed = @('github.com','raw.githubusercontent.com','gist.github.com')
$content = Get-Content $hostsPath | Where-Object {
  $line = $_
  -not ($managed | Where-Object { $line -match [regex]::Escape($_) })
}

$content += ""
$content += "# --- GitHub pins, generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ---"
foreach ($h in $chosen.Keys) {
  $content += "$($chosen[$h]) $h"
  if ($h -eq 'github.com') { $content += "$($chosen[$h]) www.github.com" }
}

$content | Set-Content $hostsPath -Encoding ASCII
ipconfig /flushdns | Out-Null

Write-Host ""
Write-Host "== hosts updated, verifying via normal DNS ==" -ForegroundColor Cyan
Start-Sleep -Seconds 1

$allOk = $true
foreach ($h in $targets.Keys) {
  $path = $targets[$h].Path
  $out = (& curl.exe -sS -o NUL -w "%{http_code}|%{time_total}" --max-time 8 -A $UA "https://$h$path" 2>&1) -join ' '
  if ($out -match '^(200|30[1278])\|') {
    $mark = 'OK '
  } else {
    $mark = 'BAD'
    $allOk = $false
  }
  Write-Host ("   {0}  {1,-34} {2}" -f $mark, $h, $out)
}

Write-Host ""
if ($allOk) {
  Write-Host "GitHub is working. Open https://github.com in your browser." -ForegroundColor Green
} else {
  Write-Host "Some domains still fail - run fix-github.cmd again." -ForegroundColor Yellow
}
Write-Host ""
if (-not $NoPause) { Read-Host "Press Enter to exit" }
Stop-Transcript | Out-Null
