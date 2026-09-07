@echo off
setlocal
set GODOT=%~dp0tools\godot\Godot_v4.7.2-stable_win64.exe
if not exist "%GODOT%" (
  echo Missing %GODOT%
  echo Copy Godot_v4.7.2-stable_win64.exe into tools\godot\
  exit /b 1
)
start "" "%GODOT%" --path "%~dp0." --editor
