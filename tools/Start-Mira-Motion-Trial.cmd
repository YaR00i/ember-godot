@echo off
setlocal
"%~dp0godot\Godot_v4.7.2-stable_win64.exe" --path "%~dp0.." --windowed --resolution 1600x900 res://scenes/landscape_compact.tscn -- --mira-motion-trial
