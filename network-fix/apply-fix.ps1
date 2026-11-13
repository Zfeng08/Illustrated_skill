$ErrorActionPreference = 'Continue'

$base   = 'C:\Users\10625\Desktop\Illustrated_skill\network-fix'
$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $base "backup-$stamp"
$log    = Join-Path $base 'apply.log'
$warpCli = 'C:\Program Files\Cloudflare\Cloudflare WARP\warp-cli.exe'

New-Item -ItemType Directory -Force -Path $backup | Out-Null
if (Test-Path $log) { Remove-Item $log -Force }

function L([string]$m) {
  $line = "{0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
  Write-Host $line
  Add-Content -Path $log -Value $line -Encoding UTF8
}

L "=== START ==="
L "backup dir: $backup"

# ---------- 1. backup everything ----------
try {
  Copy-Item 'C:\Windows\System32\drivers\etc\hosts' "$backup\hosts.bak" -Force
  L "OK  hosts backed up"
} catch { L "ERR hosts backup: $($_.Exception.Message)" }

netsh interface ipv4 show config name="WLAN" 2>&1 | Out-File "$backup\dns-before.txt" -Encoding UTF8
sc.exe qc CloudflareWARP 2>&1 | Out-File "$backup\warp-service-before.txt" -Encoding UTF8
route print -4 2>&1 | Out-File "$backup\routes-before.txt" -Encoding UTF8
if (Test-Path $warpCli) { & $warpCli status 2>&1 | Out-File "$backup\warp-status-before.txt" -Encoding UTF8 }
L "OK  dns / service / routes / warp-status saved"

# ---------- 2. set DNS FIRST (so DNS never dies when WARP stops) ----------
netsh interface ipv4 set dnsservers name="WLAN" source=static address=223.5.5.5 register=primary | Out-Null
netsh interface ipv4 add dnsservers name="WLAN" address=119.29.29.29 index=2 | Out-Null
L "OK  DNS -> 223.5.5.5 (AliDNS) + 119.29.29.29 (DNSPod)"

# ---------- 3. disconnect WARP tunnel ----------
if (Test-Path $warpCli) {
  & $warpCli disconnect 2>&1 | ForEach-Object { L "warp-cli: $_" }
  Start-Sleep -Seconds 2
}

# ---------- 4. stop service + stop auto-start ----------
try {
  Stop-Service -Name CloudflareWARP -Force -ErrorAction Stop
  L "OK  CloudflareWARP service stopped"
} catch { L "ERR stop service: $($_.Exception.Message)" }

Start-Sleep -Seconds 2
try {
  Set-Service -Name CloudflareWARP -StartupType Manual -ErrorAction Stop
  L "OK  CloudflareWARP start type -> Manual"
} catch { L "ERR set starttype: $($_.Exception.Message)" }

# ---------- 5. comment out hosts pin ----------
try {
  $hostsPath = 'C:\Windows\System32\drivers\etc\hosts'
  $content = Get-Content $hostsPath
  $changed = 0
  $out = foreach ($l in $content) {
    if ($l -match '^\s*140\.82\.116\.3\s+(www\.)?github\.com') { $changed++; "# " + $l } else { $l }
  }
  $out | Set-Content $hostsPath -Encoding ASCII
  L "OK  hosts: $changed line(s) commented out"
} catch { L "ERR hosts edit: $($_.Exception.Message)" }

# ---------- 6. flush dns ----------
ipconfig /flushdns | Out-Null
L "OK  DNS cache flushed"

# ---------- 7. verify ----------
Start-Sleep -Seconds 2
L "--- VERIFY ---"
$dnsNow = (netsh interface ipv4 show dnsservers name="WLAN" 2>&1 | Out-String)
foreach ($ln in ($dnsNow -split "`r?`n")) { if ($ln.Trim()) { L ("dns| " + $ln.Trim()) } }

$tunnelRoutes = @(route print -4 | Select-String '192\.0\.2\.1').Count
L "tunnel routes remaining: $tunnelRoutes"

$svc = Get-Service CloudflareWARP
L ("service: " + $svc.Status + " / " + $svc.StartType)

$ghLines = (Get-Content 'C:\Windows\System32\drivers\etc\hosts' | Select-String 'github').Count
L "hosts lines still referencing github (commented included): $ghLines"

L "=== DONE ==="
