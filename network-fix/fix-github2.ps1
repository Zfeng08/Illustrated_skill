param([switch]$NoPause, [switch]$ProbeOnly)

# GitHub hosts pinner v2.
# v1 only checked the HTTP status code, so a fake 200 could win the race.
# v2 also checks the response body size and a content signature, and it
# pins every host GitHub actually needs (not just github.com).

$ErrorActionPreference = 'Continue'
$hostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$base      = Split-Path -Parent $MyInvocation.MyCommand.Path
$stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup    = Join-Path $base "backup-$stamp"
New-Item -ItemType Directory -Force -Path $backup | Out-Null
Start-Transcript -Path (Join-Path $base 'fix-github2.log') -Force | Out-Null

$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36'
$probeFile = Join-Path $env:TEMP 'ghprobe.bin'

$ghPool  = @('140.82.112.3','140.82.113.3','140.82.114.3','140.82.121.3',
             '140.82.112.4','140.82.113.4','140.82.114.4','140.82.116.3',
             '20.205.243.166','20.27.177.113')
$rawPool = @('185.199.108.133','185.199.109.133','185.199.110.133','185.199.111.133')

# Each entry: pool, probe path, minimum body size, required substring, extra hostnames to pin with the same IP.
$targets = [ordered]@{
  'github.com' = @{
    Pool = $ghPool; Path = '/'; MinSize = 100000; Contains = 'github'
    Aliases = @('github.com','www.github.com'); TimeoutSec = 10
  }
  'api.github.com' = @{
    Pool = @('140.82.112.5','140.82.113.5','140.82.114.5','20.205.243.168')
    Path = '/'; MinSize = 100; Contains = 'current_user_url'; TimeoutSec = 8
  }
  'codeload.github.com' = @{
    Pool = @('140.82.112.9','140.82.113.9','140.82.114.9','140.82.116.9')
    Path = '/'; MinSize = 0; Contains = ''; Loose = $true; TimeoutSec = 8
  }
  'gist.github.com' = @{
    Pool = $ghPool; Path = '/'; MinSize = 1000; Contains = ''; TimeoutSec = 10
    Aliases = @('gist.github.com')
  }
  'raw.githubusercontent.com' = @{
    Pool = $rawPool; Path = '/github/gitignore/main/README.md'
    MinSize = 500; Contains = 'gitignore'
    Aliases = @('raw.githubusercontent.com','gist.githubusercontent.com','cloud.githubusercontent.com',
                'objects.githubusercontent.com','avatars.githubusercontent.com','camo.githubusercontent.com',
                'media.githubusercontent.com','user-images.githubusercontent.com',
                'private-user-images.githubusercontent.com',
                'avatars0.githubusercontent.com','avatars1.githubusercontent.com',
                'avatars2.githubusercontent.com','avatars3.githubusercontent.com',
                'avatars4.githubusercontent.com','avatars5.githubusercontent.com')
    TimeoutSec = 8
  }
  'github.githubassets.com' = @{
    Pool = @('185.199.108.154','185.199.109.154','185.199.110.154','185.199.111.154')
    Path = '/assets/github-favicon.png'; MinSize = 100; Contains = 'PNG'
    Aliases = @('github.githubassets.com')
    TimeoutSec = 8
  }
}

function Test-One {
  param([string]$HostName, [string]$Ip, [string]$Path, [int]$MinSize, [string]$Contains, [int]$TimeoutSec, [switch]$Loose)

  $meta = & curl.exe -sS --max-time $TimeoutSec -A $UA --resolve "${HostName}:443:${Ip}" `
            -o $probeFile -w "%{http_code}|%{time_total}|%{size_download}" "https://$HostName$Path" 2>$null
  $meta = ($meta | Out-String).Trim()
  if ($meta -notmatch '^(\d{3})\|([0-9.]+)\|(\d+)$') { return $null }
  $code = [int]$Matches[1]; $time = [double]$Matches[2]; $size = [int]$Matches[3]

  if ($Loose) {
    # TLS + an HTTP response is enough: these hosts legitimately answer 404/302 on "/".
    if ($code -lt 200 -or $code -ge 500) { return $null }
    return [pscustomobject]@{ Ip = $Ip; Code = $code; Time = $time; Size = $size }
  }

  if ($code -ne 200) { return $null }
  if ($size -lt $MinSize) { return $null }
  if ($Contains -ne '' -and (Test-Path -LiteralPath $probeFile)) {
    $ok = $false
    try {
      $bytes = [System.IO.File]::ReadAllBytes($probeFile)
      $take = [Math]::Min($bytes.Length, 200000)
      if ($take -gt 0) {
        $text = [System.Text.Encoding]::UTF8.GetString($bytes, 0, $take)
        if ($text -match [regex]::Escape($Contains)) { $ok = $true }
      }
    } catch { $ok = $false }
    if (-not $ok) { return $null }
  }
  return [pscustomobject]@{ Ip = $Ip; Code = $code; Time = $time; Size = $size }
}

$chosen = [ordered]@{}

foreach ($h in $targets.Keys) {
  $cfg = $targets[$h]
  $timeout = if ($cfg.ContainsKey('TimeoutSec')) { $cfg.TimeoutSec } else { 8 }
  $minSize = if ($cfg.ContainsKey('MinSize')) { $cfg.MinSize } else { 1 }
  $contains = if ($cfg.ContainsKey('Contains')) { $cfg.Contains } else { '' }

  Write-Host ""
  Write-Host "== $h ==" -ForegroundColor Cyan
  $good = @()
  $loose = $cfg.ContainsKey('Loose') -and $cfg.Loose
  foreach ($ip in $cfg.Pool) {
    $r = Test-One -HostName $h -Ip $ip -Path $cfg.Path -MinSize $minSize -Contains $contains -TimeoutSec $timeout -Loose:$loose
    if ($r) {
      Write-Host ("   OK  {0,-16} {1,7:N0} bytes  {2:N2}s" -f $r.Ip, $r.Size, $r.Time) -ForegroundColor Green
      $good += $r
      if ($good.Count -ge 3) { break }
    } else {
      Write-Host ("   --  {0,-16} rejected" -f $ip) -ForegroundColor DarkGray
    }
  }
  if ($good.Count -gt 0) {
    $best = $good | Sort-Object Time | Select-Object -First 1
    $chosen[$h] = $best.Ip
    Write-Host ("   => {0}  ({1:N2}s)" -f $best.Ip, $best.Time) -ForegroundColor Yellow
  } else {
    Write-Host "   => nothing reachable for this host" -ForegroundColor Red
  }
}

if ($chosen.Count -eq 0) {
  Write-Host ""
  Write-Host "No GitHub IP answered correctly. Nothing was changed." -ForegroundColor Red
  if (-not $NoPause) { Read-Host "Press Enter to exit" }
  Stop-Transcript | Out-Null
  exit 1
}

# --- rewrite the managed block in hosts ---
if ($ProbeOnly) {
  Write-Host ""
  Write-Host "ProbeOnly: hosts was not modified." -ForegroundColor Yellow
  if (-not $NoPause) { Read-Host "Press Enter to exit" }
  Stop-Transcript | Out-Null
  exit 0
}

Copy-Item -LiteralPath $hostsPath -Destination (Join-Path $backup 'hosts.bak') -Force

$beginMarker = '# >>> github-pins (managed) >>>'
$endMarker   = '# <<< github-pins (managed) <<<'

$lines = @(Get-Content -LiteralPath $hostsPath -ErrorAction SilentlyContinue)
$kept = New-Object System.Collections.Generic.List[string]
$inside = $false
foreach ($line in $lines) {
  if ($line.Trim() -eq $beginMarker) { $inside = $true; continue }
  if ($line.Trim() -eq $endMarker)   { $inside = $false; continue }
  if (-not $inside) { $kept.Add($line) }
}

$block = New-Object System.Collections.Generic.List[string]
$block.Add('')
$block.Add($beginMarker)
$block.Add("# generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') by fix-github2.ps1")
foreach ($h in $chosen.Keys) {
  $aliases = $targets[$h].Aliases
  if ($aliases) {
    foreach ($a in $aliases) { $block.Add(("{0}`t{1}" -f $chosen[$h], $a)) }
  } else {
    $block.Add(("{0}`t{1}" -f $chosen[$h], $h))
  }
}
$block.Add($endMarker)

$out = @($kept) + @($block)
Set-Content -LiteralPath $hostsPath -Value $out -Encoding ASCII
& ipconfig /flushdns | Out-Null

# --- verify through normal DNS ---
Write-Host ""
Write-Host "== verify through normal DNS ==" -ForegroundColor Cyan
Start-Sleep -Seconds 1

$checks = @(
  @{ Host = 'github.com';               Path = '/';                                        Min = 100000 },
  @{ Host = 'api.github.com';           Path = '/zen';                                     Min = 5 },
  @{ Host = 'codeload.github.com';      Path = '/';                                        Min = 1 },
  @{ Host = 'raw.githubusercontent.com'; Path = '/github/gitignore/main/README.md';         Min = 500 }
)

$allOk = $true
foreach ($c in $checks) {
  $meta = & curl.exe -sS --max-time 15 -A $UA -o NUL -w "%{http_code}|%{time_total}|%{size_download}" "https://$($c.Host)$($c.Path)" 2>$null
  $meta = ($meta | Out-String).Trim()
  $ok = $false
  if ($meta -match '^(\d{3})\|([0-9.]+)\|(\d+)$') {
    $ok = ([int]$Matches[1] -eq 200 -and [int]$Matches[3] -ge $c.Min)
  }
  if ($ok) { $mark = 'OK ' } else { $mark = 'BAD'; $allOk = $false }
  Write-Host ("   {0}  {1,-28} {2}" -f $mark, $c.Host, $meta)
}

Write-Host ""
if ($allOk) {
  Write-Host "GitHub is reachable. Open https://github.com in the browser." -ForegroundColor Green
} else {
  Write-Host "Still failing - run this script again, the block moves from time to time." -ForegroundColor Yellow
}
Write-Host ""
if (-not $NoPause) { Read-Host "Press Enter to exit" }
Stop-Transcript | Out-Null
