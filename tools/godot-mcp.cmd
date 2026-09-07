@echo off
REM KeeVeeG godot-mcp only looks at process.cwd() for project.godot.
REM Cursor launches MCP from joi-conductor, so we cd into ember-godot first.
cd /d "%~dp0.."
if not exist "project.godot" (
  echo [godot-mcp] project.godot missing in %CD% 1>&2
  exit /b 1
)
npx -y @keeveeg/godot-mcp
