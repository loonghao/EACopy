@echo off
setlocal

:: Check if VCPKG_ROOT is set, otherwise try to find vcpkg
if "%VCPKG_ROOT%"=="" (
    :: Try common locations
    if exist "C:\vcpkg" (
        set VCPKG_ROOT=C:\vcpkg
        echo VCPKG_ROOT environment variable is not set.
        echo Found vcpkg at: %VCPKG_ROOT%
    ) else if exist "%~dp0..\..\vcpkg" (
        set VCPKG_ROOT=%~dp0..\..\vcpkg
        echo VCPKG_ROOT environment variable is not set.
        echo Found vcpkg at: %VCPKG_ROOT%
    ) else (
        echo VCPKG_ROOT environment variable is not set and vcpkg not found in common locations.
        echo Please run scripts\install_vcpkg.bat first or set VCPKG_ROOT manually.
        echo Example: set VCPKG_ROOT=C:\path\to\vcpkg
        exit /b 1
    )
)

:: Verify vcpkg.exe exists
if not exist "%VCPKG_ROOT%\vcpkg.exe" (
    echo vcpkg.exe not found at %VCPKG_ROOT%
    echo Please run scripts\install_vcpkg.bat to install vcpkg.
    exit /b 1
)

echo Using vcpkg from: %VCPKG_ROOT%

:: Create build directory
@mkdir build 2>nul
@pushd build

:: Configure with CMake using vcpkg toolchain
@echo Configuring with CMake using vcpkg...
@call cmake .. -G "Visual Studio 17 2022" -A x64 ^
    -DCMAKE_TOOLCHAIN_FILE="%VCPKG_ROOT%\scripts\buildsystems\vcpkg.cmake" ^
    -DEACOPY_BUILD_TESTS:BOOL=ON

:: Build both configurations
@echo Building Release configuration...
@call cmake --build . --config Release
@echo Building Debug configuration...
@call cmake --build . --config Debug

:: Run tests
@pushd test
@echo Running Release tests...
@call ctest -C Release -V
@echo Running Debug tests...
@call ctest -C Debug

@popd
@popd

echo Build completed successfully!
endlocal
