@echo off
setlocal
cd /d "%~dp0.."
if not exist "assets\local_characters\hoshi\mira_animation_workshop.scn" (
    "%~dp0godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tools/build_mira_animation_workshop.gd
    if errorlevel 1 (
        pause
        exit /b 1
    )
)
"%~dp0godot\Godot_v4.7.2-stable_win64.exe" --path . --editor res://assets/local_characters/hoshi/mira_animation_workshop.scn
