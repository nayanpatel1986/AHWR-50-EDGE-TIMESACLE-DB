@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Create-AHWR-EDGE-Shortcuts.ps1" -Desktop
if errorlevel 1 (
  echo.
  echo AHWR-EDGE shortcuts could not be created. Review the message above.
  pause
)
