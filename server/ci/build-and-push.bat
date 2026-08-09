@echo off
chcp 65001 >nul
REM 构建并推送 CI 镜像脚本（Windows）
REM 用法: build-and-push.bat [仓库地址] [镜像名] [标签] [alpine代理源]
REM
REM Nexus 示例:
REM   build-and-push.bat 192.168.1.100:8083 readlater-ci latest https://nexus.example.com/repository/alpine-proxy
REM

setlocal EnableDelayedExpansion

set "REGISTRY=%~1"
if "%~1"=="" set "REGISTRY=192.168.1.100:8083"

set "IMAGE_NAME=%~2"
if "%~2"=="" set "IMAGE_NAME=readlater-ci"

set "TAG=%~3"
if "%~3"=="" set "TAG=latest"

set "ALPINE_REPO_URL=%~4"

set "FULL_IMAGE=%REGISTRY%/%IMAGE_NAME%:%TAG%"

echo === 构建 CI 镜像 ===
echo 目标: %FULL_IMAGE%

cd /d "%~dp0"

set "BUILD_ARGS="
if not "%~4"=="" (
  set "BUILD_ARGS=--build-arg ALPINE_REPO_URL=%~4"
)

docker build %BUILD_ARGS% -t "%FULL_IMAGE%" .
if errorlevel 1 (
    echo 构建失败
    exit /b 1
)

echo.
echo === 登录 Nexus (端口 8083) ===
docker login 192.168.1.100:8083
if errorlevel 1 (
    echo 登录失败
    exit /b 1
)

echo.
echo === 推送镜像 ===
docker push "%FULL_IMAGE%"
if errorlevel 1 (
    echo 推送失败，请先登录: docker login %REGISTRY%
    exit /b 1
)

echo.
echo === 完成 ===
echo 镜像已推送: %FULL_IMAGE%
echo.
echo 请在 Forgejo 项目设置中添加 Secrets:
echo   DOCKER_REGISTRY_USER     - Docker 仓库用户名
echo   DOCKER_REGISTRY_PASSWORD - Docker 仓库密码

endlocal
