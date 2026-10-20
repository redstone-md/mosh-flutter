@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Measure-MoshNetwork.ps1"
if errorlevel 1 echo Diagnostics failed. Keep this window and send the error text.
pause
