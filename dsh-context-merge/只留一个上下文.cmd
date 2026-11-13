@echo off
chcp 65001 >nul
title Merge Context Tabs - keep one
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0set-context-tab.ps1"
echo.
pause
