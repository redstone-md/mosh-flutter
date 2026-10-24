@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Record-MoshRuntime.ps1"
if errorlevel 1 echo Recording failed. Keep this window and send the error text.
pause
