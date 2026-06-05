@echo off
setlocal enabledelayedexpansion

echo Creating release zip...
echo.

REM Create Releases folder if it doesn't exist
if not exist "Releases" mkdir Releases

REM Find the highest existing version number in the folder
set "max_ver=0"
for %%F in ("Releases\whisper-v0.*.zip") do (
    rem Parse the version number from the filename (format: whisper-v0.X.zip)
    rem %%~nF gets the filename without extension (whisper-v0.X)
    rem We split by '.' to get the second token (the number X)
    for /f "tokens=2 delims=." %%N in ("%%~nF") do (
        if %%N GTR !max_ver! set "max_ver=%%N"
    )
)

REM Set the new version to (Highest Found + 1)
set /a version=max_ver+1
set "filename=Releases\whisper-v0.!version!.zip"

echo Creating !filename!...
git archive --format=zip --prefix=whisper/ -o !filename! HEAD 2>nul

if %ERRORLEVEL% EQU 0 (
    echo.
    echo Success! Created: !filename!
    echo.
    echo Remember to:
    echo 1. Update version in whisper.toc to 0.!version!
    echo 2. Upload this zip to GitHub releases
) else (
    echo.
    echo Error creating zip file!
)

echo.
pause