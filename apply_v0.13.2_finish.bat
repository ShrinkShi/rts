@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0apply_v0.13.2_finish.ps1"
if errorlevel 1 pause
