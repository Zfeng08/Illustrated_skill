@echo off
chcp 65001 >nul
title Fix GitHub DNS - auto probe and pin
echo Requesting administrator rights (hosts file)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','%~dp0fix-github2.ps1'"
