@echo off
chcp 65001 >nul
REM 构建 read-later-server 镜像并推送到 Docker Hub
REM 用法: push-server-to-dockerhub.bat [标签]
REM
REM 示例:
REM   push-server-to-dockerhub.bat latest
REM   push-server-to-dockerhub.bat v1.0.0

setlocal enabledelayedexpansion

set DOCKERHUB_USER=cpf23333
set TAG=%~1

if "%~1"=="" set TAG=latest

set IMAGE_NAME=%DOCKERHUB_USER%/read-later-server
set FULL_IMAGE=%IMAGE_NAME%:%TAG%
set LATEST_IMAGE=%IMAGE_NAME%:latest

echo [信息] 构建 read-later-server 镜像
echo [信息] 目标: %FULL_IMAGE%

cd /d "%~dp0\..\.."

docker build -f server/Dockerfile -t "%FULL_IMAGE%" .
if errorlevel 1 (
  echo [错误] 镜像构建失败
  exit /b 1
)

if not "%TAG%"=="latest" (
  echo.
  echo [信息] 额外标记 latest
  docker tag "%FULL_IMAGE%" "%LATEST_IMAGE%"
  if errorlevel 1 (
    echo [错误] 标记 latest 失败
    exit /b 1
  )
)

echo.
echo [信息] 登录 Docker Hub
docker login
if errorlevel 1 (
  echo [错误] Docker Hub 登录失败
  exit /b 1
)

echo.
echo [信息] 推送镜像
docker push "%FULL_IMAGE%"
if errorlevel 1 (
  echo [错误] 推送 %FULL_IMAGE% 失败
  exit /b 1
)

if not "%TAG%"=="latest" (
  docker push "%LATEST_IMAGE%"
  if errorlevel 1 (
    echo [错误] 推送 %LATEST_IMAGE% 失败
    exit /b 1
  )
)

echo.
echo [信息] 完成
echo [信息] 镜像已推送: %FULL_IMAGE%
if not "%TAG%"=="latest" (
  echo [信息] 镜像已推送: %LATEST_IMAGE%
)
