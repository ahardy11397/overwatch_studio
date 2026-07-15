@echo on
call "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat" -arch=x64 > nul 2>&1
dumpbin /dependents "F:\Drive\scripts\overwatch_studio\libs\Qt\6.6.2\msvc2019_64\qml\QtQml\WorkerScript\workerscriptplugin.dll"