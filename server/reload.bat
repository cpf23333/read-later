@echo off
REM 重新加载镜像并重启服务（用于更新）

set "TAR_FILE=read-later-server.tar"

if not exist "%TAR_FILE%" (
    echo 错误：找不到 %TAR_FILE%
    echo 请将新的镜像包复制到当前目录
    exit /b 1
)

echo === 停止现有服务 ===
docker-compose -f docker-compose.yml down 2>nul
docker stop readlater 2>nul

echo === 加载新镜像 ===
docker load -i "%TAR_FILE%"

echo === 启动服务 ===
docker-compose -f docker-compose.yml --env-file .env up -d --no-build

echo === 完成 ===
docker ps | findstr readlater
