<#
.SYNOPSIS
    Registers (or removes) the Windows scheduled tasks that keep the notes repo auto-synced.

.DESCRIPTION
    Creates two tasks:

      Illustrated_skill-AutoSync-Watch
          Starts at user logon and keeps AutoSync.ps1 running in watch mode,
          pushing changes a few seconds after you save a note.

      Illustrated_skill-AutoSync-Fallback
          Runs every 10 minutes: performs one sync pass and restarts the watcher
          if it is no longer running.

    Tasks run as the current user, so no elevation is required.
    The repository folder is never modified by this script.

.PARAMETER FallbackMinutes
    How often the fallback task runs. Default 10.

.PARAMETER Unregister
    Remove both tasks instead of creating them.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\.autosync\Register-AutoSync.ps1

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\.autosync\Register-AutoSync.ps1 -Unregister
#>
[CmdletBinding()]
param(
    [int]$FallbackMinutes = 10,
    [switch]$Unregister
)

$ErrorActionPreference = 'Stop'

$RepoRoot     = Split-Path -Parent $PSScriptRoot
$AutoSync     = Join-Path $PSScriptRoot 'AutoSync.ps1'
$FallbackSync = Join-Path $PSScriptRoot 'FallbackSync.ps1'
$RunHidden    = Join-Path $PSScriptRoot 'RunHidden.vbs'
$TaskPrefix   = 'Illustrated_skill-AutoSync'
$WatchTask    = "$TaskPrefix-Watch"
$FallbackTask = "$TaskPrefix-Fallback"

# wscript.exe is a GUI-subsystem host: it allocates no console, so the tasks never flash a
# PowerShell window (PowerShell's own -WindowStyle Hidden is not enough when Windows Terminal
# is the default console host). See the header of RunHidden.vbs.
$WscriptExe = Join-Path $env:SystemRoot 'System32\wscript.exe'

# --- Remove ----------------------------------------------------------------
if ($Unregister) {
    foreach ($name in @($WatchTask, $FallbackTask)) {
        if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $name -Confirm:$false
            Write-Host "Removed scheduled task: $name"
        } else {
            Write-Host "Not present, nothing to remove: $name"
        }
    }
    return
}

# --- Pre-flight ------------------------------------------------------------
foreach ($path in @($AutoSync, $FallbackSync, $RunHidden, $WscriptExe)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required file not found: $path" }
}
if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot '.git'))) {
    throw "Not a git repository: $RepoRoot"
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'git was not found on PATH.'
}

# --- Shared settings -------------------------------------------------------
$principal = New-ScheduledTaskPrincipal `
    -UserId ("{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME) `
    -LogonType Interactive `
    -RunLevel Limited

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)

# --- Task 1: watcher (starts at logon, runs indefinitely) -------------------
$watchAction = New-ScheduledTaskAction `
    -Execute $WscriptExe `
    -Argument ('//B //Nologo "{0}" "AutoSync.ps1"' -f $RunHidden) `
    -WorkingDirectory $RepoRoot

$watchTrigger = New-ScheduledTaskTrigger -AtLogOn -User ("{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME)

Register-ScheduledTask `
    -TaskName $WatchTask `
    -Action $watchAction `
    -Trigger $watchTrigger `
    -Settings $settings `
    -Principal $principal `
    -Description 'Watches the Illustrated_skill notes folder and pushes saves to GitHub within seconds.' `
    -Force | Out-Null

Write-Host "Registered: $WatchTask  (starts at logon)"

# --- Task 2: fallback (every N minutes) ------------------------------------
$fallbackAction = New-ScheduledTaskAction `
    -Execute $WscriptExe `
    -Argument ('//B //Nologo "{0}" "FallbackSync.ps1"' -f $RunHidden) `
    -WorkingDirectory $RepoRoot

$fallbackTrigger = New-ScheduledTaskTrigger `
    -Once `
    -At (Get-Date).AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes $FallbackMinutes) `
    -RepetitionDuration (New-TimeSpan -Days 3650)

Register-ScheduledTask `
    -TaskName $FallbackTask `
    -Action $fallbackAction `
    -Trigger $fallbackTrigger `
    -Settings $settings `
    -Principal $principal `
    -Description 'Safety net: syncs the Illustrated_skill notes repo and restarts the watcher if it died.' `
    -Force | Out-Null

Write-Host "Registered: $FallbackTask  (every $FallbackMinutes minutes)"

Write-Host ''
Get-ScheduledTask -TaskName "$TaskPrefix-*" |
    Select-Object TaskName, State |
    Format-Table -AutoSize |
    Out-String |
    Write-Host
