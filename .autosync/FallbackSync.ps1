<#
.SYNOPSIS
    Fallback entry point for the Illustrated_skill notes repository.

.DESCRIPTION
    Runs one sync pass, then makes sure the background file watcher is still alive.
    This is what the "Illustrated_skill-AutoSync-Fallback" scheduled task runs every 10 minutes,
    so a crashed or killed watcher is resurrected automatically.

.NOTES
    Requires Windows PowerShell 5.1+.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

$LogDir  = Join-Path $PSScriptRoot 'logs'
$LogFile = Join-Path $LogDir 'autosync.log'
$WatchTaskName = 'Illustrated_skill-AutoSync-Watch'

if (-not (Test-Path -LiteralPath $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

function Write-FallbackLog {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 } catch { }
    Write-Host $line
}

# 1) One sync pass.
& (Join-Path $PSScriptRoot 'AutoSync.ps1') -Once

# 2) Make sure the watcher is running.
try {
    $task = Get-ScheduledTask -TaskName $WatchTaskName -ErrorAction Stop
    if ($task.State -ne 'Running') {
        Start-ScheduledTask -TaskName $WatchTaskName
        Write-FallbackLog ('Watcher was not running (state: {0}) - restarted it.' -f $task.State) 'WARN'
    }
} catch {
    Write-FallbackLog ('Could not check the watcher task: ' + $_.Exception.Message) 'WARN'
}
