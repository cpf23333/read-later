@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul
echo ==========================================
echo ReadLater 离线部署包构建脚本
echo ==========================================
echo.

REM 配置
REM Docker 镜像源（可修改为你自己的镜像源，需要包含库路径如 library/）
if "%DOCKER_REGISTRY%"=="" set "DOCKER_REGISTRY=docker.xuanyuan.me/library/"

REM 处理镜像源
set "REGISTRY_CLEAN=%DOCKER_REGISTRY%"

REM 去除可能的协议前缀
if "%REGISTRY_CLEAN:~0,8%"=="https://" (
    set "REGISTRY_CLEAN=%REGISTRY_CLEAN:https://=%"
)
if "%REGISTRY_CLEAN:~0,7%"=="http://" (
    set "REGISTRY_CLEAN=%REGISTRY_CLEAN:http://=%"
)

REM 去除尾部斜杠
if "%REGISTRY_CLEAN:~-1%"=="/" (
    set "REGISTRY_CLEAN=%REGISTRY_CLEAN:~0,-1%"
)

REM 设置镜像和构建参数
set "BASE_IMAGE=%REGISTRY_CLEAN%/node:20-alpine"
set "BUILD_ARG_REGISTRY=--build-arg REGISTRY=%REGISTRY_CLEAN%/"

echo Docker 镜像源: %REGISTRY_CLEAN%
echo.

REM 步骤 1：检查/拉取基础镜像
echo [1/4] 检查基础镜像...

REM 检查本地是否已有镜像
docker image inspect node:20-alpine >nul 2>&1
if errorlevel 1 (
    echo   拉取 %BASE_IMAGE%...
    docker pull %BASE_IMAGE%
    if errorlevel 1 (
        echo 拉取基础镜像失败！
        pause
        exit /b 1
    )
    REM 重新打标签为官方名称，方便 Dockerfile 使用
    docker tag %BASE_IMAGE% node:20-alpine
) else (
    echo   本地已存在 node:20-alpine，跳过拉取
)
echo.

REM 步骤 2：构建应用镜像
echo [2/4] 构建应用镜像...
docker build %BUILD_ARG_REGISTRY% -t read-later-server:latest .

if errorlevel 1 (
    echo 构建失败！请检查 Docker 是否正常运行
    pause
    exit /b 1
)

REM 步骤 3：导出镜像
echo.
echo [3/4] 导出镜像（基础镜像 + 应用镜像）...
docker save node:20-alpine read-later-server:latest -o read-later-server.tar

REM 步骤 4：打包
echo.
echo [4/4] 打包部署文件...

if exist readlater-offline.zip del readlater-offline.zip
powershell -Command "Compress-Archive -Path 'docker-compose.offline.yml','read-later-server.tar','start-offline.sh','start-offline.bat','update-offline.sh','update-offline.bat','README-DEPLOY.md' -DestinationPath 'readlater-offline.zip'"

echo.
echo ==========================================
echo 构建完成！
echo 输出文件：readlater-offline.zip
echo    read-later-server.tar 已保留（可单独用于更新）
echo ==========================================
echo.
echo 包含内容：
echo   - read-later-server.tar   (Docker 镜像：包含 node:20-alpine 基础镜像)
echo   - docker-compose.offline.yml
echo   - start-offline.sh / .bat   (启动脚本)
echo   - update-offline.sh / .bat  (更新脚本)
echo   - README-DEPLOY.md
echo.
echo 说明：完全离线，目标机器无需任何外网访问
echo.
echo 部署步骤：
echo   1. 将 readlater-offline.zip 复制到目标服务器
echo   2. 解压：右键 readlater-offline.zip -^> 全部解压缩
echo   3. 启动：./start-offline.sh (Linux) 或 start-offline.bat (Windows)
echo.
echo 更新步骤：
echo   1. 重新运行此脚本生成新包
echo   2. 将新的 read-later-server.tar 复制到服务器
echo   3. 执行：./update-offline.sh (Linux) 或 update-offline.bat (Windows)
echo.

pause
