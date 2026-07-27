@echo off
setlocal
cd /d "%~dp0"

set "RA2_SOURCE=%~1"
set "RA2MD_SOURCE=%~2"
set "RA2_CSF=%~3"
set "RA2MD_CSF=%~4"
set "AUDIO_SOURCE=%~5"
set "AUDIO_MD_SOURCE=%~6"
set "EXPAND01=%~7"
set "EXPAND03=%~8"
set "EXPAND04=%~9"

if "%RA2_SOURCE%"=="" set "RA2_SOURCE=ra2.zip"
if "%RA2MD_SOURCE%"=="" set "RA2MD_SOURCE=ra2md.zip"
if "%RA2_CSF%"=="" set "RA2_CSF=ra2.csf"
if "%RA2MD_CSF%"=="" set "RA2MD_CSF=ra2md.csf"
if "%AUDIO_SOURCE%"=="" set "AUDIO_SOURCE=audio.zip"
if "%AUDIO_MD_SOURCE%"=="" set "AUDIO_MD_SOURCE=audiomd.zip"
if "%EXPAND01%"=="" set "EXPAND01=expandmd01.zip"
if "%EXPAND03%"=="" set "EXPAND03=expandmd03.zip"
if "%EXPAND04%"=="" set "EXPAND04=expandmd04.zip"

for %%F in ("%RA2_SOURCE%" "%RA2MD_SOURCE%" "%RA2_CSF%" "%RA2MD_CSF%" "%AUDIO_SOURCE%" "%AUDIO_MD_SOURCE%" "%EXPAND01%" "%EXPAND03%" "%EXPAND04%") do (
  if not exist %%F (
    echo [ERROR] Cannot find %%~F
    echo Usage: build_ra2_pipeline_windows.bat ra2.zip ra2md.zip ra2.csf ra2md.csf audio.zip audiomd.zip expandmd01.zip expandmd03.zip expandmd04.zip
    pause
    exit /b 1
  )
)

python -c "import PIL" >nul 2>nul
if errorlevel 1 (
  echo Installing Pillow for SHP and VXL preview conversion...
  python -m pip install Pillow
  if errorlevel 1 exit /b 1
)

python tools\ra2_pipeline\build_all.py ^
  --ra2 "%RA2_SOURCE%" ^
  --ra2md "%RA2MD_SOURCE%" ^
  --ra2-csf "%RA2_CSF%" ^
  --ra2md-csf "%RA2MD_CSF%" ^
  --audio "%AUDIO_SOURCE%" ^
  --audio-md "%AUDIO_MD_SOURCE%" ^
  --extra "expandmd01=%EXPAND01%" ^
  --extra "expandmd03=%EXPAND03%" ^
  --extra "expandmd04=%EXPAND04%" ^
  --project "%CD%"
if errorlevel 1 (
  echo [ERROR] RA2/YR pipeline failed.
  pause
  exit /b 1
)

echo.
echo Build completed. Open the project and choose "RA2 / YR 资源数据库".
pause
