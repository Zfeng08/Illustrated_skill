' RunHidden.vbs - launches an auto-sync PowerShell script with no console window at all.
'
' WHY THIS EXISTS
'   The scheduled tasks run inside the interactive desktop session. On Windows 11,
'   Windows Terminal is the default console host, and in that configuration PowerShell's
'   own "-WindowStyle Hidden" is not enough: the console gets delegated to Windows Terminal,
'   which puts a window on screen anyway. The result is a "PowerShell" window popping up on
'   every run (the fallback task runs every 10 minutes).
'
'   wscript.exe is a GUI-subsystem binary, so it never allocates a console of its own.
'   WshShell.Run(..., 0, ...) then asks Windows to create the child process with SW_HIDE,
'   so its console window is never created visible in the first place - there is nothing to
'   flash and nothing to hide.
'
' USAGE (from a scheduled task action - the action itself has no window either)
'   wscript.exe //B //Nologo "C:\...\.autosync\RunHidden.vbs" "AutoSync.ps1"
'   wscript.exe //B //Nologo "C:\...\.autosync\RunHidden.vbs" "FallbackSync.ps1"
'
'   //B makes wscript fail silently, so a broken launch can never raise a dialog box.

Option Explicit

Dim shell, fso, baseDir, target, psExe, extraArgs, i, cmd

' No argument -> nothing to do, exit quietly.
If WScript.Arguments.Count = 0 Then
    WScript.Quit 1
End If

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' Resolve the target script relative to this file, so the whole folder stays portable.
baseDir = fso.GetParentFolderName(WScript.ScriptFullName)
target = fso.BuildPath(baseDir, WScript.Arguments(0))

If Not fso.FileExists(target) Then
    WScript.Quit 1
End If

psExe = shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")

extraArgs = ""
For i = 1 To WScript.Arguments.Count - 1
    extraArgs = extraArgs & " " & WScript.Arguments(i)
Next

cmd = """" & psExe & """ -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ & target & """" & extraArgs

' 0 = SW_HIDE (never show a window), False = do not wait for it to finish.
shell.Run cmd, 0, False
