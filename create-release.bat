@echo off
setlocal enabledelayedexpansion

echo Creating whisper release zip...
echo.

REM Must run from the addon root (where whisper.toc lives)
if not exist "whisper.toc" (
    echo Error: whisper.toc not found. Run this script from the addon folder.
    exit /b 1
)

where git >nul 2>&1
if errorlevel 1 (
    echo Error: git is not installed or not on PATH.
    exit /b 1
)

if not exist "Releases" mkdir Releases

REM Read ## Version: from whisper.toc (source of truth)
set "version="
for /f "usebackq tokens=1,* delims=:" %%A in (`findstr /B /C:"## Version:" whisper.toc`) do (
    set "version=%%B"
)
set "version=!version: =!"

if not defined version (
    echo Error: Could not read ## Version: from whisper.toc
    exit /b 1
)

set "filename=Releases\whisper-v!version!.zip"

if exist "!filename!" (
    echo Error: !filename! already exists.
    echo Bump ## Version: in whisper.toc before creating another release.
    exit /b 1
)

echo Version: !version!
echo Output:  !filename!
echo.
echo Packing committed files from git HEAD...
echo (Commit any new modules / changes first, or they will be missing.)
echo.

REM Pack only addon files users need — not Releases/, dev scripts, or .idea/
git archive --format=zip --prefix=whisper/ -o "!filename!" HEAD ^
    whisper.toc whisper.lua whisper_Config.lua whisper_TestOverlay.lua ^
    Media Modules

if errorlevel 1 (
    echo.
    echo Error: git archive failed.
    exit /b 1
)

echo.
echo Success! Created: !filename!
echo.
echo Included from git HEAD:
echo   whisper.toc, core lua, Modules\, Media\
echo.
echo Next steps:
echo   1. Test the zip by extracting to Interface\AddOns\
echo   2. Upload !filename! to GitHub Releases
echo.

if /I "%~1"=="nopause" exit /b 0
pause
