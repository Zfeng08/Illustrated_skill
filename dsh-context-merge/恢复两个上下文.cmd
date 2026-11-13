@echo off
chcp 65001 >nul
title Merge Context Tabs - restore both
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0set-context-tab.ps1" -Hide:$false
echo.
pause
