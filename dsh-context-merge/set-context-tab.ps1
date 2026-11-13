# Toggle the duplicate "Context" tab contributed by billion-context.
#   (no switch) -> billion-context stops registering its own Context tab;
#                  dsh-context keeps the single "Context" tab, plus "Fleet".
#   -Show       -> restore billion-context's tab (two Context tabs again).
# Only edits the user config file; no admin rights, nothing under node_modules.

param(
  [switch]$Show
)

$ErrorActionPreference = 'Stop'

function Format-Json($value, [int]$indent = 0) {
  $pad  = ' ' * $indent
  $pad2 = ' ' * ($indent + 2)
  if ($null -eq $value) { return 'null' }
  if ($value -is [bool]) { if ($value) { return 'true' } else { return 'false' } }
  if ($value -is [string]) {
    $escaped = $value.Replace('\', '\\').Replace('"', '\"')
    return '"' + $escaped + '"'
  }
  if ($value -is [int] -or $value -is [long] -or $value -is [double] -or $value -is [decimal]) {
    return $value.ToString([System.Globalization.CultureInfo]::InvariantCulture)
  }
  if ($value -is [System.Collections.IDictionary]) {
    if ($value.Count -eq 0) { return '{}' }
    $lines = @()
    foreach ($key in $value.Keys) {
      $lines += $pad2 + (Format-Json ([string]$key)) + ': ' + (Format-Json $value[$key] ($indent + 2))
    }
    return "{`n" + ($lines -join ",`n") + "`n" + $pad + '}'
  }
  if ($value -is [System.Management.Automation.PSCustomObject]) {
    $props = @($value.PSObject.Properties)
    if ($props.Count -eq 0) { return '{}' }
    $lines = @()
    foreach ($prop in $props) {
      $lines += $pad2 + (Format-Json ([string]$prop.Name)) + ': ' + (Format-Json $prop.Value ($indent + 2))
    }
    return "{`n" + ($lines -join ",`n") + "`n" + $pad + '}'
  }
  if ($value -is [System.Collections.IEnumerable]) {
    $items = @($value)
    if ($items.Count -eq 0) { return '[]' }
    $lines = @()
    foreach ($item in $items) { $lines += $pad2 + (Format-Json $item ($indent + 2)) }
    return "[`n" + ($lines -join ",`n") + "`n" + $pad + ']'
  }
  return (Format-Json ([string]$value))
}

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

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
Copy-Item -LiteralPath $cfg -Destination "$cfg.bak-$stamp" -Force
Write-Host "Backup: $cfg.bak-$stamp"

$out = New-Object System.Collections.Specialized.OrderedDictionary
foreach ($p in $json.PSObject.Properties) {
  if ($p.Name -ne 'dsh') { $out[$p.Name] = $p.Value }
}

$dsh = New-Object System.Collections.Specialized.OrderedDictionary
if ($json.PSObject.Properties.Name -contains 'dsh' -and $null -ne $json.dsh) {
  foreach ($p in $json.dsh.PSObject.Properties) { $dsh[$p.Name] = $p.Value }
}
if ($Show) { $dsh['contextTab'] = $true } else { $dsh['contextTab'] = $false }
$out['dsh'] = $dsh

$text = (Format-Json $out 0) + "`n"
[System.IO.File]::WriteAllText($cfg, $text, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ""
if ($Show) {
  Write-Host "Done: billion-context's Context tab is back ON (two tabs)." -ForegroundColor Yellow
} else {
  Write-Host "Done: billion-context's duplicate Context tab is OFF." -ForegroundColor Green
  Write-Host "The remaining Context tab is dsh-context's full dashboard (plus Fleet)."
}
Write-Host ""
Write-Host "Now reload the client: press Ctrl+R in the window, or restart DSH."
Write-Host "No app rebuild or reinstall is needed."
