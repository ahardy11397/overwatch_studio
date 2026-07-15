@echo off
REM Run overwatch_studio.exe with all dependencies
call "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat" -arch=x64 > nul 2>&1
cd /d F:\Drive\scripts\overwatch_studio\build\bin\Release
set PATH=%CD%;F:\Drive\scripts\overwatch_studio\libs\Qt\6.6.2\msvc2019_64\bin;%PATH%
set QML2_IMPORT_PATH=F:\Drive\scripts\overwatch_studio\libs\Qt\6.6.2\msvc2019_64\qml;F:\Drive\scripts\overwatch_studio_override
set QT_QPA_PLATFORM_PLUGIN_PATH=%CD%\platforms
echo Starting overwatch_studio.exe...
overwatch_studio.exe
pause