@echo off
chcp 65001 >nul
REM 构建并推送 CI 镜像脚本（Windows）
REM 用法: build-and-push.bat <仓库地址> [镜像名] [标签]
REM
REM 镜像源等构建参数从当前目录的 .env 文件读取
REM 示例 .env：
REM   BASE_IMAGE=your-registry/library/node:24
REM   APT_REPO_DEBIAN=http://your-nexus/repository/debian-bookworm-proxy
REM   NPM_REGISTRY=http://your-nexus/repository/npm-proxy/
REM
REM 示例:
REM   build-and-push.bat your-registry readlater-ci latest

setlocal EnableDelayedExpansion

if "%~1"=="" (
  echo [错误] 必须指定仓库地址
  echo [用法] build-and-push.bat ^<仓库地址^> [镜像名] [标签]
  exit /b 1
)

set "REGISTRY=%~1"
set "IMAGE_NAME=%~2"
if "%~2"=="" set "IMAGE_NAME=readlater-ci"

set "TAG=%~3"
if "%~3"=="" set "TAG=latest"

set "FULL_IMAGE=%REGISTRY%/%IMAGE_NAME%:%TAG%"

echo === 构建 CI 镜像 ===
echo 目标: %FULL_IMAGE%

cd /d "%~dp0"

REM 检查 .env 文件
set "ENV_FILE=.env"
if not exist "%ENV_FILE%" (
  if exist ".env.example" (
    echo [首次运行] 从 .env.example 创建 .env
    copy ".env.example" ".env" >nul
    echo [提示] 请编辑 .env 配置镜像源，然后重新运行本脚本
    exit /b 0
  ) else (
    echo [错误] 找不到 .env 或 .env.example
    exit /b 1
  )
)

REM 加载 .env（runner 环境变量优先，不覆盖已存在的变量）
for /f "usebackq eol=# tokens=1* delims==" %%a in ("%ENV_FILE%") do (
  if not defined %%a set "%%a=%%b"
)

REM 拼装 build args
set "BUILD_ARGS="
call :AddBuildArg BASE_IMAGE
call :AddBuildArg APT_REPO_DEBIAN
call :AddBuildArg APT_REPO_SECURITY
call :AddBuildArg NPM_REGISTRY
call :AddBuildArg INSECURE_REGISTRIES

docker build %BUILD_ARGS% -t "%FULL_IMAGE%" .
if errorlevel 1 (
    echo 构建失败
    exit /b 1
)

echo.
echo === 登录仓库 ===
if defined DOCKER_REGISTRY_PASSWORD (
  echo %DOCKER_REGISTRY_PASSWORD% | docker login %REGISTRY% -u "%DOCKER_REGISTRY_USER%" --password-stdin
) else (
  docker login %REGISTRY%
)
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
exit /b 0

:AddBuildArg
set "ARG_KEY=%~1"
set "ARG_VALUE=!%ARG_KEY%!"
if not "!ARG_VALUE!"=="" (
  if "!BUILD_ARGS!"=="" (
    set "BUILD_ARGS=--build-arg !ARG_KEY!=!ARG_VALUE!"
  ) else (
    set "BUILD_ARGS=!BUILD_ARGS! --build-arg !ARG_KEY!=!ARG_VALUE!"
  )
  echo 使用 build arg: !ARG_KEY!=!ARG_VALUE!
)
exit /b 0
