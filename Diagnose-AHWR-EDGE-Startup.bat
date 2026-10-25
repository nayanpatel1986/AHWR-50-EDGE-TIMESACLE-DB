@echo off
setlocal
set "AHWR_ROOT=%~dp0"
set "AHWR_REPORT=%TEMP%\AHWR-Startup-Diagnostics.txt"
set "AHWR_POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
echo AHWR-50 Twin startup diagnostics
echo These checks do not start or stop the application or change Windows permissions.
echo Report: "%AHWR_REPORT%"
call :collect >"%AHWR_REPORT%" 2>&1
if errorlevel 1 goto report_failed
type "%AHWR_REPORT%"
echo.
echo Send AHWR-Startup-Diagnostics.txt to support, or photograph the failed check above.
if /i not "%~1"=="--no-pause" pause
exit /b 0

:report_failed
echo Could not write the report in TEMP. Showing checks on screen instead.
call :collect
if /i not "%~1"=="--no-pause" pause
exit /b 1

:collect
echo AHWR-50 Twin startup diagnostics
echo Date: %DATE% %TIME%
ver
echo Application folder: %AHWR_ROOT%
echo Architecture: %PROCESSOR_ARCHITECTURE%
echo.
echo === Required files ===
call :file "Start-AHWR-EDGE.ps1"
call :file "settings.env"
call :file "app\frontend\dist\index.html"
call :file "app\backend\server.js"
call :file "runtime\node\node.exe"
call :file "runtime\python\python.exe"
call :file "runtime\pgsql\bin\postgres.exe"
call :file "runtime\telegraf\telegraf.exe"
echo.
echo === Folder write access ===
call :writable "run"
call :writable "logs"
call :writable "data\pgdata"
echo.
echo === Windows PowerShell program check ===
echo Program: %AHWR_POWERSHELL%
if not exist "%AHWR_POWERSHELL%" goto no_powershell
"%AHWR_POWERSHELL%" -NoLogo -NoProfile -NonInteractive -Command "$PSVersionTable.PSVersion.ToString(); $ExecutionContext.SessionState.LanguageMode"
echo PowerShell exit code: %ERRORLEVEL%
goto runtime_checks

:no_powershell
echo MISSING Windows PowerShell executable

:runtime_checks
echo.
echo === Bundled runtime program checks ===
call :runtime "runtime\node\node.exe" --version
call :runtime "runtime\python\python.exe" --version
call :runtime "runtime\pgsql\bin\postgres.exe" --version
call :runtime "runtime\telegraf\telegraf.exe" --version
echo.
echo settings.env, credentials, tokens and database contents were NOT read into this report.
echo If a program reports Access is denied, ask IT to check permissions and application-control events.
exit /b 0

:file
if exist "%AHWR_ROOT%%~1" (echo OK: %~1) else (echo MISSING: %~1)
exit /b 0

:writable
if not exist "%AHWR_ROOT%%~1\" goto directory_missing
set "AHWR_PROBE=%AHWR_ROOT%%~1\ahwr-write-check-%RANDOM%-%RANDOM%.tmp"
echo write-check>"%AHWR_PROBE%"
if errorlevel 1 goto directory_denied
del /q "%AHWR_PROBE%"
if exist "%AHWR_PROBE%" goto directory_cleanup_failed
echo OK write/delete: %~1
exit /b 0

:directory_missing
echo MISSING directory: %~1
exit /b 0

:directory_denied
echo DENIED write: %~1
exit /b 0

:directory_cleanup_failed
echo DENIED deleting write-check file: %~1
exit /b 0

:runtime
if not exist "%AHWR_ROOT%%~1" exit /b 0
echo Program: %~1
"%AHWR_ROOT%%~1" %2
echo Runtime exit code: %ERRORLEVEL%
exit /b 0
