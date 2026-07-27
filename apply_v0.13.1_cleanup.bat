@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0apply_v0.13.1_cleanup.ps1"
if errorlevel 1 (
    echo.
    echo 清理失败，请查看上方错误信息。
    pause
    exit /b 1
)
pause
