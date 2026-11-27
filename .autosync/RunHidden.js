// RunHidden.js - launches an auto-sync PowerShell script with no console window at all.
//
// WHY .js AND NOT .vbs
//   This is the JScript twin of the old RunHidden.vbs. Windows 11 now raises a
//   "VBScript is deprecated" alert (event provider VBScriptDeprecationAlert) every time
//   wscript.exe runs a .vbs, which produced a toast that flashed on screen. A .js file is
//   executed by jscript.dll instead, so no VBScript is touched and no deprecation alert is
//   raised. The no-window behaviour is identical: wscript.exe is a GUI-subsystem host (it
//   allocates no console) and WshShell.Run(...,0,...) starts the child with SW_HIDE, so
//   there is no window to flash.
//
// USAGE (from a scheduled task action - the action itself has no window either)
//   wscript.exe //B //Nologo "C:\...\.autosync\RunHidden.js" "AutoSync.ps1"
//   wscript.exe //B //Nologo "C:\...\.autosync\RunHidden.js" "FallbackSync.ps1"
//
//   //B makes wscript fail silently, so a broken launch can never raise a dialog box.

var a = WScript.Arguments;
if (a.length === 0) {
    WScript.Quit(1);
}

var shell = new ActiveXObject("WScript.Shell");
var fso   = new ActiveXObject("Scripting.FileSystemObject");

// Resolve the target script relative to this file, so the whole folder stays portable.
var baseDir = fso.GetParentFolderName(WScript.ScriptFullName);
var target  = fso.BuildPath(baseDir, a(0));

if (!fso.FileExists(target)) {
    WScript.Quit(1);
}

var psExe = shell.ExpandEnvironmentStrings("%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe");

var extraArgs = "";
for (var i = 1; i < a.length; i++) {
    extraArgs += " " + a(i);
}

var cmd = '"' + psExe + '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + target + '"' + extraArgs;

// 0 = SW_HIDE (never show a window), false = do not wait for it to finish.
shell.Run(cmd, 0, false);
