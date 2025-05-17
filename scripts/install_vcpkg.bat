@echo off
setlocal

:: Check if VCPKG_ROOT is already set, otherwise use default C:\vcpkg
if "%VCPKG_ROOT%"=="" (
    set VCPKG_DIR=C:\vcpkg
    echo VCPKG_ROOT not set. Using default location: %VCPKG_DIR%
) else (
    set VCPKG_DIR=%VCPKG_ROOT%
    echo Using existing VCPKG_ROOT: %VCPKG_DIR%
)

:: Force absolute path for default location
if "%VCPKG_ROOT%"=="" (
    set VCPKG_DIR=C:\vcpkg
)

:: Check if vcpkg directory already exists
if exist "%VCPKG_DIR%" (
    echo vcpkg already exists at %VCPKG_DIR%
    goto :setup_env
)

:: Clone vcpkg repository
echo Cloning vcpkg repository...
git clone https://github.com/microsoft/vcpkg.git "%VCPKG_DIR%"
if %ERRORLEVEL% neq 0 (
    echo Failed to clone vcpkg repository.
    exit /b 1
)

:: Bootstrap vcpkg
echo Bootstrapping vcpkg...
pushd "%VCPKG_DIR%"
call bootstrap-vcpkg.bat
if %ERRORLEVEL% neq 0 (
    echo Failed to bootstrap vcpkg.
    exit /b 1
)
popd

:setup_env
:: Set VCPKG_ROOT environment variable if not already set
if "%VCPKG_ROOT%"=="" (
    echo Setting VCPKG_ROOT environment variable...
    setx VCPKG_ROOT "%VCPKG_DIR%"
    set VCPKG_ROOT=%VCPKG_DIR%
) else (
    echo VCPKG_ROOT already set to: %VCPKG_ROOT%
)

:: Add vcpkg to PATH for current session
set PATH=%VCPKG_DIR%;%PATH%

echo.
echo vcpkg has been installed successfully!
echo VCPKG_ROOT is set to: %VCPKG_ROOT%
echo.
echo IMPORTANT: You need to restart your command prompt or IDE for the environment variables to take effect.
echo If you want to build immediately without restarting, run:
echo.
echo     set VCPKG_ROOT=%VCPKG_DIR%
echo     scripts\build.bat
echo.

endlocal & set VCPKG_ROOT=%VCPKG_DIR%
