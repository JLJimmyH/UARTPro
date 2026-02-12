@echo off
setlocal enabledelayedexpansion

cd /d "%~dp0"

:: --- Auto-detect Visual Studio via vswhere ---
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
    echo [ERROR] vswhere.exe not found. Please install Visual Studio.
    pause
    exit /b 1
)

for /f "delims=" %%i in ('"%VSWHERE%" -latest -property installationPath') do set "VS_PATH=%%i"
if not defined VS_PATH (
    echo [ERROR] Visual Studio installation not found.
    pause
    exit /b 1
)

call "%VS_PATH%\VC\Auxiliary\Build\vcvars64.bat"

:: --- Clean and build ---
rd /s /q build 2>nul
mkdir build
cd build

cmake .. -G "Ninja" -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="D:/Qt/6.7.3/msvc2022_64"
if %errorlevel% neq 0 (
    echo CMake config failed!
    pause
    exit /b 1
)

cmake --build . --config Release
if %errorlevel% neq 0 (
    echo Build failed!
    pause
    exit /b 1
)

echo Build succeeded!
