@echo off
setlocal
"%~dp0godot\Godot_v4.7.2-stable_win64.exe" --path "%~dp0.." --windowed --resolution 1600x900 --max-fps 30 res://scenes/wing_flight_trial.tscn -- --hoshi-wings
