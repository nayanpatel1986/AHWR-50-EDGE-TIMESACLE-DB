@echo off
setlocal
echo AHWR-50 Twin startup
echo [1/3] Checking the extracted application folder...
pushd "%~dp0" 2>nul
if errorlevel 1 goto folder_failed
if not exist "%~dp0Start-AHWR-EDGE.ps1" goto files_missing
set "AHWR_PORTABLE=1"
set "AHWR_POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
echo [2/3] Checking Windows PowerShell...
if not exist "%AHWR_POWERSHELL%" goto powershell_missing
"%AHWR_POWERSHELL%" -NoLogo -NoProfile -NonInteractive -Command "exit 0"
if errorlevel 1 goto powershell_failed
echo [3/3] Starting the database, dashboard and collectors...
"%AHWR_POWERSHELL%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-AHWR-EDGE.ps1"
set "AHWR_START_EXIT=%ERRORLEVEL%"
if not "%AHWR_START_EXIT%"=="0" goto startup_failed
popd
exit /b 0

:folder_failed
echo Cannot open the application folder. Fully extract the ZIP into a local folder you can access.
goto failed

:files_missing
echo Start-AHWR-EDGE.ps1 is missing. Extract the complete ZIP before starting.
goto failed

:powershell_missing
echo Windows PowerShell was not found at "%AHWR_POWERSHELL%".
echo Ask your IT support to check the Windows PowerShell installation.
goto failed

:powershell_failed
echo Windows could not run PowerShell. The application startup script has not run.
echo Run Diagnose-AHWR-EDGE-Startup.bat and give its report to IT support.
echo An access restriction or application-control rule may need IT review.
goto failed

:startup_failed
echo.
echo AHWR-EDGE startup returned exit code %AHWR_START_EXIT%.
echo Review the error above and run Diagnose-AHWR-EDGE-Startup.bat.
echo The application logs are in the logs folder.
goto failed

:failed
if not defined AHWR_NO_PAUSE pause
exit /b 1
