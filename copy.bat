@echo off
set SCRIPT_DIR=%~dp0
set APP_NAME=UARTPro.exe

if not exist "%SCRIPT_DIR%build\%APP_NAME%" (
    echo [ERROR] %APP_NAME% not found in build\
    pause
    exit /b 1
)

if not exist "%SCRIPT_DIR%bin\" (
    echo [ERROR] bin\ not found. Please run deploy.bat first.
    pause
    exit /b 1
)

copy /Y "%SCRIPT_DIR%build\%APP_NAME%" "%SCRIPT_DIR%bin\" >nul
echo Copied %APP_NAME% to bin\
