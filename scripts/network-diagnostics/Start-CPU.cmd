@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Measure-MoshCpu.ps1"
if errorlevel 1 echo Recording failed. Keep this window and send the error text.
pause
