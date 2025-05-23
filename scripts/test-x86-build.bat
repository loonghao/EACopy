@echo off
REM Test script for x86 build issues
REM This script tests the x86 build configuration locally

setlocal enabledelayedexpansion

echo Testing x86 build configuration...

REM Check if VCPKG_ROOT is set
if not defined VCPKG_ROOT (
    echo VCPKG_ROOT is not set. Please set it to your vcpkg installation directory.
    echo Example: set VCPKG_ROOT=C:\vcpkg
    exit /b 1
)

echo VCPKG_ROOT: %VCPKG_ROOT%

REM Create test build directory
set BUILD_DIR=build-test-x86
if exist %BUILD_DIR% (
    echo Cleaning existing build directory...
    rmdir /s /q %BUILD_DIR%
)

mkdir %BUILD_DIR%
cd %BUILD_DIR%

echo Configuring CMake for x86...
cmake .. ^
    -G "Visual Studio 17 2022" ^
    -A Win32 ^
    -DCMAKE_TOOLCHAIN_FILE="%VCPKG_ROOT%\scripts\buildsystems\vcpkg.cmake" ^
    -DVCPKG_TARGET_TRIPLET=x86-windows ^
    -DEACOPY_BUILD_TESTS=OFF ^
    -DEACOPY_BUILD_AS_LIBRARY=ON ^
    -DEACOPY_INSTALL=ON

if %ERRORLEVEL% neq 0 (
    echo CMake configuration failed!
    cd ..
    exit /b 1
)

echo Building Debug configuration...
cmake --build . --config Debug

if %ERRORLEVEL% neq 0 (
    echo Debug build failed!
    cd ..
    exit /b 1
)

echo Building Release configuration...
cmake --build . --config Release

if %ERRORLEVEL% neq 0 (
    echo Release build failed!
    cd ..
    exit /b 1
)

echo Testing install...
cmake --install . --config Release --prefix install-test

if %ERRORLEVEL% neq 0 (
    echo Install failed!
    cd ..
    exit /b 1
)

cd ..

echo ✅ x86 build test completed successfully!
echo Build artifacts are in: %BUILD_DIR%
echo Installed files are in: %BUILD_DIR%\install-test

endlocal
