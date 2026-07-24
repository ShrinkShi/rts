@echo off
setlocal
where godot.exe >nul 2>nul
if %errorlevel%==0 (
  godot.exe --editor --path "%~dp0"
  exit /b 0
)
where Godot_v4.7-stable_win64.exe >nul 2>nul
if %errorlevel%==0 (
  Godot_v4.7-stable_win64.exe --editor --path "%~dp0"
  exit /b 0
)
echo 未在 PATH 中找到 Godot。请在 Godot 项目管理器中导入：%~dp0project.godot
pause
