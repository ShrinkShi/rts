@echo off
chcp 65001 >nul
echo 请先确认 Godot 已完全关闭。
python tools\repair_ra2_audio_sources.py
if errorlevel 1 (
  echo 修复失败，请检查 Python 3 是否可用。
  pause
  exit /b 1
)
if exist .godot (
  echo 正在删除旧的 Godot 导入缓存...
  rmdir /s /q .godot
)
echo 修复完成。现在重新打开 project.godot，并等待资源导入结束。
pause
