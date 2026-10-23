@echo off
setlocal
set "PSModulePath="
cd /d "%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Export-ExistingCpu.ps1" %*
set "result=%errorlevel%"
pause
exit /b %result%
