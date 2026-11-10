@echo off
chcp 65001 >nul
REM Build and push the mobile CI image (readlater-android-ci)
REM
REM Usage:
REM   build-and-push.bat [image-version] [--push-only^|--build-only]
REM
REM Examples:
REM   build-and-push.bat 3.38.10-r2
REM   build-and-push.bat 3.38.10-r2 --push-only
REM   build-and-push.bat 3.38.10-r2 --build-only
REM
REM Environment:
REM   CI_REGISTRY      Registry (mobile\ci\.env)
REM   IMAGE_NAME       Image name, default readlater-android-ci
REM   IMAGE_VERSION    Version used when no argument is given
REM   NODE_IMAGE       Node image, default node:24-bookworm-slim
REM   PUB_HOSTED_URL   pub mirror, default https://pub.flutter-io.cn
REM   PUSH_RETRIES     Push attempts, default 5

setlocal
for %%I in ("%~dp0..\..") do set "ROOT=%%~fI"
if exist "%~dp0.env" for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%~dp0.env") do set "%%A=%%B"

set "MODE=build-push"
set "VERSION="
:parse_args
if "%~1"=="" goto parsed_args
if /I "%~1"=="--push-only" (
  set "MODE=push-only"
  shift
  goto parse_args
)
if /I "%~1"=="--build-only" (
  set "MODE=build-only"
  shift
  goto parse_args
)
if /I "%~1"=="--help" goto usage
if not defined VERSION set "VERSION=%~1"
shift
goto parse_args
:usage
echo Usage: build-and-push.bat [image-version] [--push-only^|--build-only]
exit /b 0
:parsed_args

if not defined VERSION if defined IMAGE_VERSION set "VERSION=%IMAGE_VERSION%"
if not defined FLUTTER_BASE_VERSION set "FLUTTER_BASE_VERSION=3.38.10"
if not defined VERSION (
  for /f %%i in ('powershell -NoProfile -Command "(Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmm')"') do set "VERSION=%FLUTTER_BASE_VERSION%-%%i"
)
if not defined IMAGE_NAME set "IMAGE_NAME=readlater-android-ci"
if not defined NODE_IMAGE set "NODE_IMAGE=node:24-bookworm-slim"
if not defined PUB_HOSTED_URL set "PUB_HOSTED_URL=https://pub.flutter-io.cn"
if not defined PUSH_RETRIES set "PUSH_RETRIES=5"

if not defined CI_REGISTRY (
  echo [ERROR] CI_REGISTRY is not set. Put it in mobile\ci\.env
  exit /b 1
)
if not defined SDK_IMAGE (
  echo [ERROR] SDK_IMAGE is not set. Put it in mobile\ci\.env
  exit /b 1
)

set "FULL_IMAGE=%CI_REGISTRY%/%IMAGE_NAME%:%VERSION%"

echo === Mobile CI image ===
echo Target: %FULL_IMAGE%
echo Mode: %MODE%
echo IMAGE_VERSION: %VERSION%

cd /d "%ROOT%"

if /I "%MODE%"=="push-only" goto push_image
if /I "%MODE%"=="build-only" goto build_image
goto build_image

:build_image
echo.
echo === Build image ===
echo NODE_IMAGE: %NODE_IMAGE%
echo PUB_HOSTED_URL: %PUB_HOSTED_URL%
echo SDK_IMAGE: %SDK_IMAGE%
docker build ^
  --build-arg "IMAGE_VERSION=%VERSION%" ^
  --build-arg "NODE_IMAGE=%NODE_IMAGE%" ^
  --build-arg "PUB_HOSTED_URL=%PUB_HOSTED_URL%" ^
  --build-arg "SDK_IMAGE=%SDK_IMAGE%" ^
  -f "%ROOT%\mobile\ci\Dockerfile" ^
  -t "%FULL_IMAGE%" ^
  "%ROOT%\mobile"
if errorlevel 1 (
  echo [ERROR] Image build failed
  exit /b 1
)
if /I "%MODE%"=="build-only" goto done

:push_image
echo.
docker image inspect "%FULL_IMAGE%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Local image not found: %FULL_IMAGE%
  echo Build it first without --push-only.
  exit /b 1
)

set /a ATTEMPT=0
:push_loop
set /a ATTEMPT+=1
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
echo Image: %FULL_IMAGE%
echo.
echo Forgejo Variables:
echo   MOBILE_CI_IMAGE         = %FULL_IMAGE%
echo   MOBILE_CI_IMAGE_VERSION = %VERSION%
echo.
echo Refresh dind:
echo   docker exec docker_dind docker rmi %FULL_IMAGE% ^|^| true
echo   docker exec docker_dind docker pull %FULL_IMAGE%

:done
endlocal
