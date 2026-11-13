# Toggle the duplicate "Context" tab contributed by billion-context.
#   -Hide  (default) -> billion-context stops registering its own Context tab;
#                       dsh-context keeps the single "Context" tab, plus "Fleet".
#   -Hide:$false     -> restore billion-context's tab (two tabs again).
# Only edits the user config file; no admin rights, no files in node_modules.

param(
  [switch]$Hide = $true
)

$ErrorActionPreference = 'Stop'

$cfg = Join-Path $env:USERPROFILE '.config\billion-context\billion-context.json'
if (-not (Test-Path -LiteralPath $cfg)) {
  Write-Host "Config not found: $cfg" -ForegroundColor Red
  Write-Host "Open the DSH client once so billion-context writes its config, then retry."
  exit 1
}

$raw = Get-Content -LiteralPath $cfg -Raw -Encoding UTF8
try { $json = $raw | ConvertFrom-Json } catch {
  Write-Host "Config is not valid JSON, refusing to touch it: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
Copy-Item -LiteralPath $cfg -Destination "$cfg.bak-$stamp" -Force
Write-Host "Backup: $cfg.bak-$stamp"

# Rebuild as an ordered object so 'providers' keeps its place.
$out = [ordered]@{}
foreach ($p in $json.PSObject.Properties) {
  if ($p.Name -ne 'dsh') { $out[$p.Name] = $p.Value }
}

$dsh = [ordered]@{}
if ($json.PSObject.Properties.Name -contains 'dsh' -and $null -ne $json.dsh) {
  foreach ($p in $json.dsh.PSObject.Properties) { $dsh[$p.Name] = $p.Value }
}
$dsh['contextTab'] = -not $Hide.IsPresent
$out['dsh'] = $dsh

$text = ($out | ConvertTo-Json -Depth 8) + "`n"
[System.IO.File]::WriteAllText($cfg, $text, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ""
if ($Hide) {
  Write-Host "Done: billion-context's duplicate Context tab is OFF." -ForegroundColor Green
  Write-Host "The remaining Context tab is dsh-context's full dashboard (plus Fleet)."
} else {
  Write-Host "Done: billion-context's Context tab is back ON (two tabs)." -ForegroundColor Yellow
}
Write-Host ""
Write-Host "Now reload the client: press Ctrl+R in the window, or restart DSH."
Write-Host "No app rebuild or reinstall is needed."
