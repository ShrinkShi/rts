@echo off
setlocal
cd /d "%~dp0"
if not exist "ra2.zip" (
  echo Missing ra2.zip in project root.
  pause
  exit /b 1
)
if not exist "ra2md.zip" (
  echo Missing ra2md.zip in project root.
  pause
  exit /b 1
)
python tools\ra2_full_database.py ra2.zip ra2md.zip data\ra2
if errorlevel 1 (
  echo Database build failed.
  pause
  exit /b 1
)
echo RA2/YR database rebuilt successfully.
pause
