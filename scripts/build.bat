@echo off
setlocal

:: Check if VCPKG_ROOT is set
if "%VCPKG_ROOT%"=="" (
    echo VCPKG_ROOT environment variable is not set.
    echo Please set VCPKG_ROOT to your vcpkg installation directory.
    echo Example: set VCPKG_ROOT=C:\vcpkg
    exit /b 1
)

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
