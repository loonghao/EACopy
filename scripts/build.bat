@echo off
setlocal enabledelayedexpansion

:: ============================================================================
:: EACopy Build Script
:: ============================================================================
:: This script builds EACopy for different architectures and configurations
:: Supports both local development and CI environments
:: ============================================================================

:: Initialize logging and timing
set "BUILD_START_TIME=%TIME%"
set "LOG_LEVEL=INFO"

echo.
echo ============================================================================
echo EACopy Build Script
echo ============================================================================
echo Build started at: %BUILD_START_TIME%
echo.

:: Parse command line arguments
set "ARCH=x64"
set "CONFIG=both"
set "CLEAN=auto"
set "TESTS=ON"
set "VERBOSE=OFF"
set "BUILD_DIR=build"

:parse_args
if "%~1"=="" goto :args_done
if /i "%~1"=="--arch" (
    set "ARCH=%~2"
    shift
    shift
    goto :parse_args
)
if /i "%~1"=="--config" (
    set "CONFIG=%~2"
    shift
    shift
    goto :parse_args
)
if /i "%~1"=="--clean" (
    set "CLEAN=yes"
    shift
    goto :parse_args
)
if /i "%~1"=="--no-clean" (
    set "CLEAN=no"
    shift
    goto :parse_args
)
if /i "%~1"=="--no-tests" (
    set "TESTS=OFF"
    shift
    goto :parse_args
)
if /i "%~1"=="--verbose" (
    set "VERBOSE=ON"
    shift
    goto :parse_args
)
if /i "%~1"=="--build-dir" (
    set "BUILD_DIR=%~2"
    shift
    shift
    goto :parse_args
)
if /i "%~1"=="--help" (
    goto :show_help
)
echo Unknown argument: %~1
goto :show_help

:args_done

:: Validate architecture
if /i not "%ARCH%"=="x64" if /i not "%ARCH%"=="x86" if /i not "%ARCH%"=="Win32" (
    echo Error: Invalid architecture '%ARCH%'. Supported: x64, x86, Win32
    exit /b 1
)

:: Normalize x86 to Win32 for Visual Studio
if /i "%ARCH%"=="x86" set "ARCH=Win32"

:: Validate configuration
if /i not "%CONFIG%"=="Debug" if /i not "%CONFIG%"=="Release" if /i not "%CONFIG%"=="both" (
    echo Error: Invalid configuration '%CONFIG%'. Supported: Debug, Release, both
    exit /b 1
)

call :log_info "Build Configuration:"
call :log_info "  Architecture: %ARCH%"
call :log_info "  Configuration: %CONFIG%"
call :log_info "  Tests: %TESTS%"
call :log_info "  Clean: %CLEAN%"
call :log_info "  Build Directory: %BUILD_DIR%"
call :log_info "  Verbose: %VERBOSE%"
echo.

:: Check environment
call :check_environment
if errorlevel 1 exit /b 1

:: Check if VCPKG_ROOT is set, otherwise try to find vcpkg
if "%VCPKG_ROOT%"=="" (
    call :log_info "Searching for vcpkg installation..."
    :: Try common locations
    if exist "C:\vcpkg\vcpkg.exe" (
        set VCPKG_ROOT=C:\vcpkg
        call :log_info "Found vcpkg at: !VCPKG_ROOT!"
    ) else if exist "%GITHUB_WORKSPACE%\vcpkg\vcpkg.exe" (
        :: GitHub Actions workspace path
        set VCPKG_ROOT=%GITHUB_WORKSPACE%\vcpkg
        call :log_info "Found vcpkg at GitHub Actions workspace: !VCPKG_ROOT!"
    ) else if exist "%USERPROFILE%\vcpkg\vcpkg.exe" (
        set VCPKG_ROOT=%USERPROFILE%\vcpkg
        call :log_info "Found vcpkg at user profile: !VCPKG_ROOT!"
    ) else (
        call :log_error "VCPKG_ROOT environment variable is not set and vcpkg not found in common locations."
        call :log_error "Please run scripts\install_vcpkg.bat first or set VCPKG_ROOT manually."
        call :log_error "Example: set VCPKG_ROOT=C:\path\to\vcpkg"
        exit /b 1
    )
) else (
    call :log_info "Using vcpkg from VCPKG_ROOT: %VCPKG_ROOT%"
)

:: Verify vcpkg.exe exists
if not exist "%VCPKG_ROOT%\vcpkg.exe" (
    echo Error: vcpkg.exe not found at %VCPKG_ROOT%
    echo Please run scripts\install_vcpkg.bat to install vcpkg.
    exit /b 1
)

echo Using vcpkg from: %VCPKG_ROOT%
echo.

:: Handle build directory cleaning
call :handle_build_directory

:: Configure CMake
call :configure_cmake
if errorlevel 1 (
    echo Error: CMake configuration failed
    exit /b 1
)

:: Build configurations
if /i "%CONFIG%"=="both" (
    call :build_config "Release"
    if errorlevel 1 exit /b 1
    call :build_config "Debug"
    if errorlevel 1 exit /b 1
) else (
    call :build_config "%CONFIG%"
    if errorlevel 1 exit /b 1
)

:: Run tests if enabled
if /i "%TESTS%"=="ON" (
    call :run_tests
)

call :calculate_build_time
echo.
echo ============================================================================
echo Build completed successfully!
echo ============================================================================
call :log_info "Build outputs are in: %BUILD_DIR%"
call :log_info "  - EACopy.exe: %BUILD_DIR%\Release\EACopy.exe"
call :log_info "  - EACopyService.exe: %BUILD_DIR%\Release\EACopyService.exe"
call :log_info "  - EACopyLib.lib: %BUILD_DIR%\Release\EACopyLib.lib"
echo.
call :log_info "Build completed in: %BUILD_DURATION%"
echo.
goto :eof

:: ============================================================================
:: Functions
:: ============================================================================

:show_help
echo.
echo Usage: build.bat [options]
echo.
echo Options:
echo   --arch ^<x64^|x86^>        Target architecture (default: x64)
echo   --config ^<Debug^|Release^|both^>  Build configuration (default: both)
echo   --clean                  Force clean build directory
echo   --no-clean               Skip cleaning build directory
echo   --no-tests               Skip running tests
echo   --verbose                Enable verbose output
echo   --build-dir ^<dir^>        Custom build directory (default: build)
echo   --help                   Show this help message
echo.
echo Examples:
echo   build.bat                          # Build both Debug and Release for x64
echo   build.bat --arch x86 --config Release  # Build Release for x86
echo   build.bat --clean --no-tests       # Clean build without tests
echo.
exit /b 0

:handle_build_directory
echo Checking build directory: %BUILD_DIR%
if exist "%BUILD_DIR%" (
    echo Build directory already exists.

    :: Determine if we should clean
    set "SHOULD_CLEAN=no"
    if /i "%CLEAN%"=="yes" set "SHOULD_CLEAN=yes"
    if /i "%CLEAN%"=="auto" (
        :: Check if running in CI environment (GitHub Actions sets CI=true)
        if "%CI%"=="true" (
            echo Running in CI environment, automatically cleaning build directory...
            set "SHOULD_CLEAN=yes"
        ) else (
            echo It's recommended to clean it before building with vcpkg.
            choice /C YN /M "Do you want to clean the build directory"
            if errorlevel 2 set "SHOULD_CLEAN=no"
            if errorlevel 1 set "SHOULD_CLEAN=yes"
        )
    )

    if "!SHOULD_CLEAN!"=="yes" (
        echo Cleaning build directory...
        rmdir /S /Q "%BUILD_DIR%" 2>nul
        if exist "%BUILD_DIR%" (
            echo Warning: Could not completely clean build directory
        ) else (
            echo Build directory cleaned successfully
        )
    )
)

:: Create build directory
echo Creating build directory: %BUILD_DIR%
mkdir "%BUILD_DIR%" 2>nul
if not exist "%BUILD_DIR%" (
    echo Error: Could not create build directory: %BUILD_DIR%
    exit /b 1
)
goto :eof

:configure_cmake
echo.
echo ============================================================================
echo Configuring CMake
echo ============================================================================
pushd "%BUILD_DIR%"

set "CMAKE_ARGS=-G "Visual Studio 17 2022" -A %ARCH%"
set "CMAKE_ARGS=%CMAKE_ARGS% -DCMAKE_TOOLCHAIN_FILE="%VCPKG_ROOT%\scripts\buildsystems\vcpkg.cmake""
set "CMAKE_ARGS=%CMAKE_ARGS% -DEACOPY_BUILD_TESTS:BOOL=%TESTS%"

if /i "%VERBOSE%"=="ON" (
    set "CMAKE_ARGS=%CMAKE_ARGS% --verbose"
)

echo Running: cmake .. %CMAKE_ARGS%
echo.
call cmake .. %CMAKE_ARGS%
set "CMAKE_RESULT=%ERRORLEVEL%"
popd

if not "%CMAKE_RESULT%"=="0" (
    call :log_error "CMake configuration failed with exit code %CMAKE_RESULT%"
    call :log_error "Common causes:"
    call :log_error "  - Missing dependencies (vcpkg packages not installed)"
    call :log_error "  - Invalid VCPKG_ROOT path: %VCPKG_ROOT%"
    call :log_error "  - Missing Visual Studio 2022 with C++ support"
    call :log_error "  - Architecture mismatch"
    call :log_error "Check the CMake output above for specific error details"
    exit /b %CMAKE_RESULT%
)

echo CMake configuration completed successfully
goto :eof

:build_config
set "BUILD_CONFIG=%~1"
echo.
echo ============================================================================
echo Building %BUILD_CONFIG% configuration
echo ============================================================================
pushd "%BUILD_DIR%"

set "BUILD_ARGS=--build . --config %BUILD_CONFIG%"
if /i "%VERBOSE%"=="ON" (
    set "BUILD_ARGS=%BUILD_ARGS% --verbose"
)

echo Running: cmake %BUILD_ARGS%
echo.
call cmake %BUILD_ARGS%
set "BUILD_RESULT=%ERRORLEVEL%"
popd

if not "%BUILD_RESULT%"=="0" (
    call :log_error "Build failed for %BUILD_CONFIG% configuration with exit code %BUILD_RESULT%"
    call :log_error "Common causes:"
    call :log_error "  - Compilation errors in source code"
    call :log_error "  - Missing header files or libraries"
    call :log_error "  - Linker errors"
    call :log_error "  - Insufficient disk space"
    call :log_error "Check the build output above for specific error details"
    exit /b %BUILD_RESULT%
)

echo %BUILD_CONFIG% build completed successfully
goto :eof

:run_tests
echo.
echo ============================================================================
echo Running Tests
echo ============================================================================
pushd "%BUILD_DIR%"

if exist "test" (
    pushd test

    if /i "%CONFIG%"=="both" (
        echo Running Release tests...
        call ctest -C Release -V
        echo.
        echo Running Debug tests...
        call ctest -C Debug -V
    ) else (
        echo Running %CONFIG% tests...
        call ctest -C %CONFIG% -V
    )

    popd
) else (
    echo Warning: Test directory not found, skipping tests
)

popd
goto :eof

:: ============================================================================
:: Logging and Utility Functions
:: ============================================================================

:log_info
echo [INFO] %~1
goto :eof

:log_warn
echo [WARN] %~1
goto :eof

:log_error
echo [ERROR] %~1
goto :eof

:check_environment
call :log_info "Checking build environment..."

:: Check Windows version
for /f "tokens=4-5 delims=. " %%i in ('ver') do set "WIN_VERSION=%%i.%%j"
call :log_info "Windows version: %WIN_VERSION%"

:: Check Visual Studio
if exist "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\" (
    call :log_info "Visual Studio 2022 Build Tools detected"
) else if exist "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\" (
    call :log_info "Visual Studio 2022 Community detected"
) else if exist "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Tools\MSVC\" (
    call :log_info "Visual Studio 2022 Professional detected"
) else if exist "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Tools\MSVC\" (
    call :log_info "Visual Studio 2022 Enterprise detected"
) else (
    call :log_error "Visual Studio 2022 not found. Please install Visual Studio 2022 with C++ support."
    exit /b 1
)

:: Check CMake
cmake --version >nul 2>&1
if errorlevel 1 (
    call :log_error "CMake not found. Please install CMake and add it to PATH."
    exit /b 1
) else (
    for /f "tokens=3" %%i in ('cmake --version 2^>nul ^| findstr "cmake version"') do (
        call :log_info "CMake version: %%i"
    )
)

call :log_info "Environment check completed"
goto :eof

:calculate_build_time
set "BUILD_END_TIME=%TIME%"

:: Convert times to seconds for calculation
call :time_to_seconds "%BUILD_START_TIME%" BUILD_START_SECONDS
call :time_to_seconds "%BUILD_END_TIME%" BUILD_END_SECONDS

:: Calculate duration
set /a "DURATION_SECONDS=%BUILD_END_SECONDS% - %BUILD_START_SECONDS%"

:: Handle day rollover
if %DURATION_SECONDS% lss 0 (
    set /a "DURATION_SECONDS=%DURATION_SECONDS% + 86400"
)

:: Convert back to readable format
set /a "HOURS=%DURATION_SECONDS% / 3600"
set /a "MINUTES=(%DURATION_SECONDS% %% 3600) / 60"
set /a "SECONDS=%DURATION_SECONDS% %% 60"

if %HOURS% gtr 0 (
    set "BUILD_DURATION=%HOURS%h %MINUTES%m %SECONDS%s"
) else if %MINUTES% gtr 0 (
    set "BUILD_DURATION=%MINUTES%m %SECONDS%s"
) else (
    set "BUILD_DURATION=%SECONDS%s"
)

goto :eof

:time_to_seconds
set "TIME_STR=%~1"
set "RESULT_VAR=%~2"

:: Parse time string (HH:MM:SS.MS)
for /f "tokens=1-3 delims=:." %%a in ("%TIME_STR%") do (
    set "HOURS=%%a"
    set "MINUTES=%%b"
    set "SECONDS=%%c"
)

:: Remove leading zeros to avoid octal interpretation
set /a "HOURS=1%HOURS% - 100"
set /a "MINUTES=1%MINUTES% - 100"
set /a "SECONDS=1%SECONDS% - 100"

:: Convert to total seconds
set /a "%RESULT_VAR%=%HOURS% * 3600 + %MINUTES% * 60 + %SECONDS%"
goto :eof

:check_environment
call :log_info "Checking build environment..."

:: Check Windows version
for /f "tokens=4-5 delims=. " %%i in ('ver') do set "WIN_VERSION=%%i.%%j"
call :log_info "Windows version: %WIN_VERSION%"

:: Check Visual Studio
if exist "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\" (
    call :log_info "Visual Studio 2022 Build Tools detected"
) else if exist "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\" (
    call :log_info "Visual Studio 2022 Community detected"
) else if exist "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Tools\MSVC\" (
    call :log_info "Visual Studio 2022 Professional detected"
) else if exist "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Tools\MSVC\" (
    call :log_info "Visual Studio 2022 Enterprise detected"
) else (
    call :log_error "Visual Studio 2022 not found. Please install Visual Studio 2022 with C++ support."
    exit /b 1
)

:: Check CMake
cmake --version >nul 2>&1
if errorlevel 1 (
    call :log_error "CMake not found. Please install CMake and add it to PATH."
    exit /b 1
) else (
    for /f "tokens=3" %%i in ('cmake --version 2^>nul ^| findstr "cmake version"') do (
        call :log_info "CMake version: %%i"
    )
)

:: Check PowerShell (for CI compatibility)
powershell -Command "Get-Host" >nul 2>&1
if errorlevel 1 (
    call :log_warn "PowerShell not available, some CI features may not work"
) else (
    for /f "tokens=*" %%i in ('powershell -Command "$PSVersionTable.PSVersion.ToString()" 2^>nul') do (
        call :log_info "PowerShell version: %%i"
    )
)

call :log_info "Environment check completed"
goto :eof

:calculate_build_time
set "BUILD_END_TIME=%TIME%"

:: Convert times to seconds for calculation
call :time_to_seconds "%BUILD_START_TIME%" BUILD_START_SECONDS
call :time_to_seconds "%BUILD_END_TIME%" BUILD_END_SECONDS

:: Calculate duration
set /a "DURATION_SECONDS=%BUILD_END_SECONDS% - %BUILD_START_SECONDS%"

:: Handle day rollover
if %DURATION_SECONDS% lss 0 (
    set /a "DURATION_SECONDS=%DURATION_SECONDS% + 86400"
)

:: Convert back to readable format
set /a "HOURS=%DURATION_SECONDS% / 3600"
set /a "MINUTES=(%DURATION_SECONDS% %% 3600) / 60"
set /a "SECONDS=%DURATION_SECONDS% %% 60"

if %HOURS% gtr 0 (
    set "BUILD_DURATION=%HOURS%h %MINUTES%m %SECONDS%s"
) else if %MINUTES% gtr 0 (
    set "BUILD_DURATION=%MINUTES%m %SECONDS%s"
) else (
    set "BUILD_DURATION=%SECONDS%s"
)

goto :eof

:time_to_seconds
set "TIME_STR=%~1"
set "RESULT_VAR=%~2"

:: Parse time string (HH:MM:SS.MS)
for /f "tokens=1-3 delims=:." %%a in ("%TIME_STR%") do (
    set "HOURS=%%a"
    set "MINUTES=%%b"
    set "SECONDS=%%c"
)

:: Remove leading zeros to avoid octal interpretation
set /a "HOURS=1%HOURS% - 100"
set /a "MINUTES=1%MINUTES% - 100"
set /a "SECONDS=1%SECONDS% - 100"

:: Convert to total seconds
set /a "%RESULT_VAR%=%HOURS% * 3600 + %MINUTES% * 60 + %SECONDS%"
goto :eof
