@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run_water_lab.ps1"
if errorlevel 1 pause
