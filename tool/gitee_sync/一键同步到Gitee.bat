@echo off
setlocal
set "SCRIPT=%~dp0sync_to_gitee.py"
set "PYEXE=C:\Users\BrianLiu\AppData\Local\Programs\Python\Python312\python.exe"
if exist "%PYEXE%" (
    "%PYEXE%" "%SCRIPT%"
) else (
    py -3.12 "%SCRIPT%"
)
echo.
pause
