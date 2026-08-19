@echo off
title Steam Shortcut Fixer v2.0 - GUI
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Steam-Shortcut-Fixer.ps1"
if errorlevel 1 pause
