@echo off
chcp 65001 >nul
REM Build and push the Android SDK base image (readlater-android-sdk)
REM
REM Usage:
REM   build-sdk.bat [sdk-version]
REM
REM Example:
REM   build-sdk.bat 3.38.10-r1
REM
REM Environment:
REM   CI_REGISTRY       Registry (mobile\ci\.env)
REM   SDK_IMAGE_NAME    Image name, default readlater-android-sdk
REM   SDK_VERSION       Version used when no argument is given, default 3.38.10-r1
REM   FLUTTER_IMAGE     Flutter base image, default ghcr.io/cirruslabs/flutter:3.38.10
REM   PUSH_RETRIES      Push attempts, default 5

setlocal
if exist "%~dp0.env" for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%~dp0.env") do set "%%A=%%B"

set "SDK_VERSION=%~1"
if not defined FLUTTER_BASE_VERSION set "FLUTTER_BASE_VERSION=3.38.10"
if not defined SDK_VERSION (
  for /f %%i in ('powershell -NoProfile -Command "(Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmm')"') do set "SDK_VERSION=%FLUTTER_BASE_VERSION%-%%i"
)
if not defined SDK_IMAGE_NAME set "SDK_IMAGE_NAME=readlater-android-sdk"
if not defined FLUTTER_IMAGE set "FLUTTER_IMAGE=ghcr.io/cirruslabs/flutter:3.38.10"
if not defined PUSH_RETRIES set "PUSH_RETRIES=5"

if not defined CI_REGISTRY (
  echo [ERROR] CI_REGISTRY is not set. Put it in mobile\ci\.env
  exit /b 1
)
if not defined SDK_TEST_BASE_URL (
  echo [ERROR] SDK_TEST_BASE_URL is not set. Put it in mobile\ci\.env
  exit /b 1
)

set "FULL_IMAGE=%CI_REGISTRY%/%SDK_IMAGE_NAME%:%SDK_VERSION%"

echo === Build Android SDK base image ===
echo Target: %FULL_IMAGE%
echo FLUTTER_IMAGE: %FLUTTER_IMAGE%
echo SDK_TEST_BASE_URL: %SDK_TEST_BASE_URL%

cd /d "%~dp0..\.."

docker build ^
  --build-arg "FLUTTER_IMAGE=%FLUTTER_IMAGE%" ^
  --build-arg "SDK_TEST_BASE_URL=%SDK_TEST_BASE_URL%" ^
  --build-arg "SDK_REVISION=%SDK_VERSION%" ^
  -f mobile/ci/Dockerfile.sdk ^
  -t "%FULL_IMAGE%" ^
  mobile/ci
if errorlevel 1 (
  echo [ERROR] SDK image build failed
  exit /b 1
)

set /a ATTEMPT=0
:push_loop
set /a ATTEMPT+=1
echo.
echo === Push attempt %ATTEMPT%/%PUSH_RETRIES% ===
docker push "%FULL_IMAGE%"
if not errorlevel 1 goto push_ok
if %ATTEMPT% GEQ %PUSH_RETRIES% goto push_failed
echo [WARN] Push failed, retry in 10s...
timeout /t 10 /nobreak >nul
goto push_loop

:push_failed
echo [ERROR] Push failed after %PUSH_RETRIES% attempts
exit /b 1

:push_ok
echo.
echo === Done ===
echo SDK image: %FULL_IMAGE%
echo.
echo Build CI image with:
echo   set SDK_IMAGE=%FULL_IMAGE%
echo   build-and-push.bat 3.38.10-r2
echo.
echo If the SDK version changes, also update the default SDK_IMAGE in mobile/ci/Dockerfile.

endlocal
