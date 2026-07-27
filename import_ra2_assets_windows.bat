\
@echo off
setlocal
cd /d "%~dp0"

where py >nul 2>nul
if %errorlevel%==0 (
    set "PYTHON=py -3"
) else (
    set "PYTHON=python"
)

%PYTHON% -c "import PIL" >nul 2>nul
if not %errorlevel%==0 (
    echo [INFO] Installing Pillow for the RA2 asset converter...
    %PYTHON% -m pip install -r tools\requirements.txt
    if not %errorlevel%==0 goto :error
)

%PYTHON% tools\ra2_import.py --project-root . scan assets\ra2_sources\samples assets\ra2_imported --config assets\ra2_sources\samples\ra2_import.json
if not %errorlevel%==0 goto :error

echo.
echo Import finished. Return to Godot and rescan the FileSystem dock if needed.
pause
exit /b 0

:error
echo.
echo Import failed. Check Python 3, Pillow, source file names, palette and JSON config.
pause
exit /b 1
