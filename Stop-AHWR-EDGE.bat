@echo off
setlocal
cd /d "%~dp0"
set "AHWR_PORTABLE=1"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Stop-AHWR-EDGE.ps1" -All
pause
