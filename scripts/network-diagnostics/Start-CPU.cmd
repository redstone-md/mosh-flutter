@echo off
cd /d "%~dp0"
set "MOSH_CPU_POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if defined PROCESSOR_ARCHITEW6432 set "MOSH_CPU_POWERSHELL=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%MOSH_CPU_POWERSHELL%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Measure-MoshCpu.ps1"
if errorlevel 1 echo Recording failed. Keep this window and send the error text.
pause
