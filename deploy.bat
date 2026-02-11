@echo off
setlocal enabledelayedexpansion

:: ============================================================
::  UARTPro Deploy Script
::  Copy exe + Qt DLLs + MSVC Runtime into .\bin
::
::  Qt path and MSVC path are auto-detected from CMakeCache.txt
::  Just run this script from the UARTPro folder (or double-click)
:: ============================================================

:: --- Script directory as base (where this .bat lives) ---
set SCRIPT_DIR=%~dp0
set APP_NAME=appUARTPro.exe

:: --- Auto-detect build directory (prefer Release, fallback Debug) ---
:: Scan build\ for subdirectories that contain both CMakeCache.txt and the exe
set BUILD_DIR=
set BUILD_TYPE=

:: First pass: look for Release builds
for /f "delims=" %%d in ('dir /b /ad "%SCRIPT_DIR%build" 2^>nul') do (
    if exist "%SCRIPT_DIR%build\%%d\%APP_NAME%" (
        echo %%d | findstr /i "\-Release" >nul && (
            set "BUILD_DIR=%SCRIPT_DIR%build\%%d"
            set "BUILD_TYPE=Release"
        )
    )
)

:: Second pass: if no Release found, take any Debug
if not defined BUILD_DIR (
    for /f "delims=" %%d in ('dir /b /ad "%SCRIPT_DIR%build" 2^>nul') do (
        if exist "%SCRIPT_DIR%build\%%d\%APP_NAME%" (
            echo %%d | findstr /i "\-Debug" >nul && (
                set "BUILD_DIR=%SCRIPT_DIR%build\%%d"
                set "BUILD_TYPE=Debug"
            )
        )
    )
)

if not defined BUILD_DIR (
    echo [ERROR] %APP_NAME% not found in any build subdirectory.
    echo         Please build the project in Qt Creator first.
    pause
    exit /b 1
)

:: --- Parse CMakeCache.txt for Qt and MSVC paths ---
set CMAKE_CACHE=%BUILD_DIR%\CMakeCache.txt
if not exist "%CMAKE_CACHE%" (
    echo [ERROR] CMakeCache.txt not found in build directory.
    echo         Please configure/build the project in Qt Creator first.
    pause
    exit /b 1
)

:: Extract CMAKE_PREFIX_PATH (Qt root, e.g. D:/Qt/6.7.3/msvc2022_64)
set QT_ROOT=
for /f "tokens=2 delims==" %%a in ('findstr /b "CMAKE_PREFIX_PATH:PATH=" "%CMAKE_CACHE%"') do (
    set "QT_ROOT=%%a"
)
if not defined QT_ROOT (
    echo [ERROR] Cannot find CMAKE_PREFIX_PATH in CMakeCache.txt
    pause
    exit /b 1
)
:: Convert forward slashes to backslashes
set QT_ROOT=%QT_ROOT:/=\%
set QT_BIN=%QT_ROOT%\bin

if not exist "%QT_BIN%\windeployqt6.exe" (
    echo [ERROR] windeployqt6.exe not found at: %QT_BIN%
    pause
    exit /b 1
)

:: Extract CMAKE_CXX_COMPILER to find MSVC install root
:: e.g. C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/MSVC/14.37.32822/bin/HostX64/x64/cl.exe
set CXX_COMPILER=
for /f "tokens=2 delims==" %%a in ('findstr /b "CMAKE_CXX_COMPILER:STRING=" "%CMAKE_CACHE%"') do (
    set "CXX_COMPILER=%%a"
)
if not defined CXX_COMPILER (
    for /f "tokens=2 delims==" %%a in ('findstr /b "CMAKE_CXX_COMPILER:FILEPATH=" "%CMAKE_CACHE%"') do (
        set "CXX_COMPILER=%%a"
    )
)
set CXX_COMPILER=%CXX_COMPILER:/=\%

:: Derive VS root: go up from .../VC/Tools/MSVC/xx.xx/bin/HostX64/x64/cl.exe to .../
:: We need: ...\VC\Redist\MSVC\<version>\x64\Microsoft.VC143.CRT
:: First get the VS install root (up to Community/Professional/Enterprise level)
set VCRT_DIR=
if defined CXX_COMPILER (
    :: Walk up: cl.exe -> x64 -> HostX64 -> bin -> <ver> -> MSVC -> Tools -> VC -> <edition>
    for %%i in ("%CXX_COMPILER%") do set "CL_DIR=%%~dpi"
    :: Go up 6 levels from bin\HostX64\x64\ to get to VS edition root
    for %%i in ("!CL_DIR!\..\..\..\..\..\..\..") do set "VS_ROOT=%%~fi"
    :: Now find the latest Redist directory
    set REDIST_BASE=!VS_ROOT!\VC\Redist\MSVC
    if exist "!REDIST_BASE!" (
        :: Pick the latest versioned subfolder
        for /f "delims=" %%d in ('dir /b /ad /on "!REDIST_BASE!" 2^>nul ^| findstr /v "^v"') do (
            set "REDIST_VER=%%d"
        )
        if defined REDIST_VER (
            set VCRT_DIR=!REDIST_BASE!\!REDIST_VER!\x64\Microsoft.VC143.CRT
        )
    )
)

echo ============================================================
echo  UARTPro Deploy  [%BUILD_TYPE%]
echo  Qt:   %QT_ROOT%
if defined VCRT_DIR echo  VCRT: !VCRT_DIR!
echo ============================================================
echo.

:: --- Step 1: Create bin dir and copy exe ---
set BIN_DIR=%SCRIPT_DIR%bin

if exist "%BIN_DIR%" (
    echo [1/3] Cleaning old bin directory...
    rmdir /s /q "%BIN_DIR%"
)

mkdir "%BIN_DIR%"
echo [1/3] Copying %APP_NAME% to bin\...
copy /Y "%BUILD_DIR%\%APP_NAME%" "%BIN_DIR%\" >nul
if errorlevel 1 (
    echo [ERROR] Failed to copy %APP_NAME%
    pause
    exit /b 1
)
echo       OK

:: --- Step 2: Run windeployqt6 ---
echo [2/3] Running windeployqt6...

"%QT_BIN%\windeployqt6.exe" --qmldir "%SCRIPT_DIR%." "%BIN_DIR%\%APP_NAME%"
if errorlevel 1 (
    echo [ERROR] windeployqt6 failed!
    pause
    exit /b 1
)
echo       OK

:: --- Step 3: Copy MSVC Runtime ---
echo [3/3] Copying MSVC Runtime DLLs...

if not defined VCRT_DIR (
    echo [WARN] Could not auto-detect MSVC Runtime path from CMakeCache.
    echo        You may need to copy vcruntime140.dll manually.
    goto :deploy_done
)

if not exist "!VCRT_DIR!" (
    echo [WARN] MSVC Runtime dir not found: !VCRT_DIR!
    echo        You may need to copy vcruntime140.dll manually.
    goto :deploy_done
)

copy /Y "!VCRT_DIR!\vcruntime140.dll"   "%BIN_DIR%\" >nul 2>nul && echo       Copied vcruntime140.dll
copy /Y "!VCRT_DIR!\vcruntime140_1.dll" "%BIN_DIR%\" >nul 2>nul && echo       Copied vcruntime140_1.dll
copy /Y "!VCRT_DIR!\msvcp140.dll"       "%BIN_DIR%\" >nul 2>nul && echo       Copied msvcp140.dll
copy /Y "!VCRT_DIR!\msvcp140_1.dll"     "%BIN_DIR%\" >nul 2>nul && echo       Copied msvcp140_1.dll
copy /Y "!VCRT_DIR!\msvcp140_2.dll"     "%BIN_DIR%\" >nul 2>nul && echo       Copied msvcp140_2.dll
copy /Y "!VCRT_DIR!\concrt140.dll"      "%BIN_DIR%\" >nul 2>nul && echo       Copied concrt140.dll
echo       OK

:deploy_done
:: --- Done ---
echo.
echo ============================================================
echo  Deploy complete!
echo  Output: %BIN_DIR%\
echo  Build:  %BUILD_TYPE%
echo ============================================================
echo.
pause
