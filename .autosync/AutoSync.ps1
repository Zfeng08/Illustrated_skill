<#
.SYNOPSIS
    Auto-sync watcher for the Illustrated_skill notes repository.

.DESCRIPTION
    Watches the repository folder and pushes changes to GitHub automatically.
    Each sync pass runs:  git add -A  ->  git commit (if staged)  ->  git pull --rebase  ->  git push

    Modes:
      (default)   Watch mode: keeps running, syncs a few seconds after the last change.
      -Once       Runs a single sync pass and exits (used by the scheduled-task fallback).

.PARAMETER Once
    Perform exactly one sync pass, then exit.

.PARAMETER DebounceSeconds
    Seconds of quiet time after the last file change before syncing. Default 8.

.PARAMETER IdleSyncMinutes
    In watch mode, force a sync at least this often even with no detected change. Default 10.

.NOTES
    Requires Windows PowerShell 5.1+ and git on PATH.
    Log file: <repo>\.autosync\logs\autosync.log
#>
[CmdletBinding()]
param(
    [switch]$Once,
    [int]$DebounceSeconds = 8,
    [int]$IdleSyncMinutes = 10
)

$ErrorActionPreference = 'Continue'

# --- Constants --------------------------------------------------------------
$RepoRoot    = Split-Path -Parent $PSScriptRoot
$LogDir      = Join-Path $PSScriptRoot 'logs'
$LogFile     = Join-Path $LogDir 'autosync.log'
$MutexName   = 'Global\IllustratedSkillAutoSync'
$MaxLogBytes = 1MB

# Directories that must never trigger a sync: git's own metadata plus this script's runtime
# files. Both the directory itself AND its contents are matched - watching only for the
# "dir/" prefix would let a bare ".git" event through and re-trigger the watcher forever.
$IgnoredDirectories = @('.git', '.autosync/logs', '.autosync/state')

# Avoid a hard dependency on the machine's code page for git's UTF-8 output.
try {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [Console]::OutputEncoding = $utf8NoBom
    $OutputEncoding = $utf8NoBom
} catch { }

if (-not (Test-Path -LiteralPath $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# --- Helpers ----------------------------------------------------------------
function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try {
        if ((Test-Path -LiteralPath $LogFile) -and ((Get-Item -LiteralPath $LogFile).Length -gt $MaxLogBytes)) {
            $keep = Get-Content -LiteralPath $LogFile -Tail 300
            Set-Content -LiteralPath $LogFile -Value $keep -Encoding UTF8
        }
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    } catch { }
    Write-Host $line
}

function Invoke-Git {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $raw  = & git -C $RepoRoot @Arguments 2>&1
    $code = $LASTEXITCODE
    $text = (($raw | ForEach-Object { $_.ToString() }) -join "`n").Trim()
    return [pscustomobject]@{ ExitCode = $code; Output = $text }
}

function Test-IgnoredPath {
    param([string]$RelativePath)
    if ([string]::IsNullOrEmpty($RelativePath)) { return $false }
    $p = $RelativePath.Replace('\', '/').TrimStart('/')

    foreach ($dir in $IgnoredDirectories) {
        if ($p.Equals($dir, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ($p.StartsWith($dir + '/', [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    if ($p -like '*.lock') { return $true }
    # Scratch files/dirs created by editors and the note-writing tools.
    if ($p -like '*.tmp' -or $p -like '*.tmpdir' -or $p -like '~$*') { return $true }
    return $false
}

function New-RepoWatcher {
    $w = New-Object System.IO.FileSystemWatcher
    $w.Path                   = $RepoRoot
    $w.IncludeSubdirectories  = $true
    $w.NotifyFilter           = [System.IO.NotifyFilters]::FileName -bor
                                [System.IO.NotifyFilters]::DirectoryName -bor
                                [System.IO.NotifyFilters]::LastWrite -bor
                                [System.IO.NotifyFilters]::Size -bor
                                [System.IO.NotifyFilters]::CreationTime
    $w.InternalBufferSize     = 65536
    $w.EnableRaisingEvents    = $true
    return $w
}

# --- Core sync --------------------------------------------------------------
function Invoke-SyncPass {
    $mutex  = $null
    $locked = $false
    try {
        # A cross-process mutex keeps the watcher and the fallback task from colliding.
        try {
            $mutex  = New-Object System.Threading.Mutex($false, $MutexName)
            $locked = $mutex.WaitOne(0)
        } catch {
            $mutex  = $null
            $locked = $true    # if locking is unavailable, still do the sync
        }
        if (-not $locked) {
            Write-Log 'Another sync is already running - skipping this round.' 'WARN'
            return
        }

        # 1) Stage everything.
        $null = Invoke-Git -Arguments @('add', '-A')

        # 2) Commit when something is staged.
        $diff    = Invoke-Git -Arguments @('diff', '--cached', '--name-only')
        $changed = @()
        if ($diff.Output) {
            $changed = @($diff.Output -split "`r?`n" | Where-Object { $_ -ne '' })
        }

        if ($changed.Count -gt 0) {
            $stamp   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            $preview = ($changed | Select-Object -First 5) -join ', '
            if ($changed.Count -gt 5) { $preview += (' (+' + ($changed.Count - 5) + ' more)') }
            $message = "notes: auto-sync $stamp`n`n$preview"

            $commit = Invoke-Git -Arguments @('commit', '-m', $message, '--quiet')
            if ($commit.ExitCode -eq 0) {
                Write-Log ('Committed {0} file(s): {1}' -f $changed.Count, $preview)
            } else {
                Write-Log ('Commit failed: ' + $commit.Output) 'ERROR'
                return
            }
        }

        # 3) Make sure the branch tracks a remote.
        $upstream = Invoke-Git -Arguments @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}')
        if ($upstream.ExitCode -ne 0) {
            Write-Log 'No upstream configured - setting it now.'
            $init = Invoke-Git -Arguments @('push', '-u', 'origin', 'HEAD')
            if ($init.ExitCode -eq 0) { Write-Log 'Initial push done.' }
            else { Write-Log ('Initial push failed: ' + $init.Output) 'WARN' }
            return
        }

        # 4) Anything to push?
        $aheadProbe = Invoke-Git -Arguments @('rev-list', '--count', '@{u}..HEAD')
        $ahead      = 0
        if ($aheadProbe.ExitCode -eq 0) { [void][int]::TryParse($aheadProbe.Output, [ref]$ahead) }

        if ($ahead -le 0) {
            Write-Log 'Nothing to push - already up to date.'
            return
        }

        Write-Log ('{0} commit(s) ahead of the remote - pushing.' -f $ahead)

        # 5) Integrate remote work first (single-user repo, so this is usually a no-op).
        $pull = Invoke-Git -Arguments @('pull', '--rebase', '--autostash', '--quiet')
        if ($pull.ExitCode -ne 0) {
            Write-Log ('pull --rebase failed (offline or conflict): ' + $pull.Output) 'WARN'
            $rebaseMerge = Join-Path $RepoRoot '.git\rebase-merge'
            $rebaseApply = Join-Path $RepoRoot '.git\rebase-apply'
            if ((Test-Path -LiteralPath $rebaseMerge) -or (Test-Path -LiteralPath $rebaseApply)) {
                $null = Invoke-Git -Arguments @('rebase', '--abort')
                Write-Log 'Aborted the rebase. Local commits are kept and will be retried.' 'WARN'
                return
            }
        }

        # 6) Push.
        $push = Invoke-Git -Arguments @('push', '--quiet')
        if ($push.ExitCode -eq 0) {
            Write-Log 'Push OK.'
        } else {
            Write-Log ('Push failed - will retry on the next sync: ' + $push.Output) 'WARN'
        }
    } finally {
        if ($null -ne $mutex) {
            if ($locked) { try { [void]$mutex.ReleaseMutex() } catch { } }
            try { $mutex.Dispose() } catch { }
        }
    }
}

# --- Watch loop -------------------------------------------------------------
function Start-WatchLoop {
    Write-Log ('Watcher started. Repo: {0} | debounce {1}s | idle sync every {2} min' -f $RepoRoot, $DebounceSeconds, $IdleSyncMinutes)

    $watcher  = New-RepoWatcher
    $lastSync = Get-Date

    while ($true) {
        $change = $null
        try {
            $change = $watcher.WaitForChanged([System.IO.WatcherChangeTypes]::All, 30000)
        } catch {
            Write-Log ('Watcher failed, rebuilding: ' + $_.Exception.Message) 'WARN'
            try { $watcher.Dispose() } catch { }
            Start-Sleep -Seconds 5
            try   { $watcher = New-RepoWatcher }
            catch { Write-Log ('Rebuild failed: ' + $_.Exception.Message) 'ERROR'; Start-Sleep -Seconds 30 }
            continue
        }

        if ($change.TimedOut) {
            if (((Get-Date) - $lastSync).TotalMinutes -ge $IdleSyncMinutes) {
                Write-Log 'Idle check.'
                Invoke-SyncPass
                $lastSync = Get-Date
            }
            continue
        }

        if (Test-IgnoredPath -RelativePath $change.Name) { continue }

        Write-Log ('Change detected: {0} ({1}) - waiting for a quiet period.' -f $change.Name, $change.ChangeType)

        # Debounce: keep extending until no non-ignored change arrives for N seconds.
        $quiet = $false
        while (-not $quiet) {
            $more = $null
            try   { $more = $watcher.WaitForChanged([System.IO.WatcherChangeTypes]::All, ($DebounceSeconds * 1000)) }
            catch { $quiet = $true; break }

            if ($more.TimedOut) { $quiet = $true }
            elseif (-not (Test-IgnoredPath -RelativePath $more.Name)) {
                Write-Log ('  still changing: ' + $more.Name)
            }
        }

        Invoke-SyncPass
        $lastSync = Get-Date
    }
}

# --- Entry point ------------------------------------------------------------
if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot '.git'))) {
    Write-Log ('Not a git repository: ' + $RepoRoot) 'ERROR'
    exit 1
}

if ($Once) {
    Write-Log 'Running a single sync pass (-Once).'
    Invoke-SyncPass
    exit 0
}

Start-WatchLoop
