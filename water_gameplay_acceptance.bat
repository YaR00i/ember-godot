@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run_water_gameplay_acceptance.ps1" %*
if errorlevel 1 pause
