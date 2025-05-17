@echo off
setlocal

:: Set vcpkg installation directory
set VCPKG_DIR=%~dp0..\..\vcpkg

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
:: Set VCPKG_ROOT environment variable
setx VCPKG_ROOT "%VCPKG_DIR%"
set VCPKG_ROOT=%VCPKG_DIR%

:: Add vcpkg to PATH for current session
set PATH=%VCPKG_DIR%;%PATH%

echo.
echo vcpkg has been installed successfully!
echo VCPKG_ROOT has been set to: %VCPKG_ROOT%
echo.
echo You may need to restart your command prompt or IDE for the environment variables to take effect.
echo.

endlocal & set VCPKG_ROOT=%VCPKG_DIR%
