@echo off
REM Build MSI installer using WiX v7 CLI
REM Requires: WiX Toolset v7 installed (winget install WiXToolset.WiXCLI)
REM Run from the repo root after a Release build.

setlocal
set PATH=C:\Program Files\WiX Toolset v7.0\bin;%PATH%
set BINDIR=%~dp0build\bin\Release
set OUTDIR=%~dp0build\msi
set VERSION=0.1.0

if not exist "%BINDIR%\overwatch_studio.exe" (
    echo ERROR: Build Release first: cmake --build build --config Release
    exit /b 1
)

if not exist "%OUTDIR%" mkdir "%OUTDIR%"

echo Building MSI installer for Overwatch Studio v%VERSION%...

REM Copy Qt DLLs from local Qt installation (if available)
if exist "%~dp0libs\Qt\6.6.2\msvc2019_64\bin" (
    echo Copying Qt runtime DLLs...
    copy /Y "%~dp0libs\Qt\6.6.2\msvc2019_64\bin\Qt6Core.dll" "%BINDIR%" 2>nul
    copy /Y "%~dp0libs\Qt\6.6.2\msvc2019_64\bin\Qt6Gui.dll" "%BINDIR%" 2>nul
    copy /Y "%~dp0libs\Qt\6.6.2\msvc2019_64\bin\Qt6Qml.dll" "%BINDIR%" 2>nul
    copy /Y "%~dp0libs\Qt\6.6.2\msvc2019_64\bin\Qt6Quick.dll" "%BINDIR%" 2>nul
    copy /Y "%~dp0libs\Qt\6.6.2\msvc2019_64\bin\Qt6QuickControls2.dll" "%BINDIR%" 2>nul
    copy /Y "%~dp0libs\Qt\6.6.2\msvc2019_64\bin\Qt6Network.dll" "%BINDIR%" 2>nul
    copy /Y "%~dp0libs\Qt\6.6.2\msvc2019_64\bin\Qt6QmlModels.dll" "%BINDIR%" 2>nul
    copy /Y "%~dp0libs\Qt\6.6.2\msvc2019_64\bin\Qt6OpenGL.dll" "%BINDIR%" 2>nul
)

REM Build the MSI
wix build "%~dp0installer_v7.wxs" ^
    -d SourceDir="%BINDIR%" ^
    -o "%OUTDIR%\OverwatchStudio-v%VERSION%.msi" ^
    -arch x64

if %ERRORLEVEL% EQU 0 (
    echo SUCCESS: MSI created at "%OUTDIR%\OverwatchStudio-v%VERSION%.msi"
) else (
    echo ERROR: MSI build failed (exit code %ERRORLEVEL%)
    exit /b %ERRORLEVEL%
)