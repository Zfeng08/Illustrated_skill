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
    # The task action is wscript, which exits as soon as it spawns the hidden watcher,
    # so $task.State returns to Ready while the watcher is still alive. Check the
    # watcher process itself, otherwise every run starts one more watcher (leak).
    $alive = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop |
        Where-Object { $_.CommandLine -like '*AutoSync.ps1*' }).Count
    # The watcher logs every idle check, so a silent log means it is wedged (e.g. blocked
    # on the log file itself). Kill it so the check below starts a fresh one.
    if ($alive -gt 0) {
        $staleMin = ((Get-Date) - (Get-Item -LiteralPath $LogFile).LastWriteTime).TotalMinutes
        if ($staleMin -gt 15) {
            foreach ($w in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
                Where-Object { $_.CommandLine -like '*AutoSync.ps1*' })) {
                Stop-Process -Id $w.ProcessId -Force -ErrorAction SilentlyContinue
            }
            Write-FallbackLog ('Watcher was stuck ({0:N0} min without log output) - killed it.' -f $staleMin) 'WARN'
            $alive = 0
        }
    }
    if ($alive -eq 0) {
        Start-ScheduledTask -TaskName $WatchTaskName
        Write-FallbackLog ('No watcher process was running (task state: {0}) - restarted it.' -f $task.State) 'WARN'
    }
} catch {
    Write-FallbackLog ('Could not check the watcher task: ' + $_.Exception.Message) 'WARN'
}
