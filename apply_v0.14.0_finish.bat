@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0apply_v0.14.0_finish.ps1"
if errorlevel 1 (
 echo.
 echo 补丁清理失败，请查看上方错误。
 pause
 exit /b 1
)
pause
