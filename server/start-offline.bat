@echo off
chcp 65001 >nul
echo ==========================================
echo ReadLater Server 离线启动脚本
echo ==========================================
echo.

REM 检测 docker compose 命令（兼容新版和旧版）
docker compose version >nul 2>&1
if errorlevel 1 (
    docker-compose version >nul 2>&1
    if errorlevel 1 (
        echo 错误：未找到 docker compose 命令
        echo 请确保 Docker 和 Docker Compose 已安装
        pause
        exit /b 1
    ) else (
        set "COMPOSE_CMD=docker-compose"
    )
) else (
    set "COMPOSE_CMD=docker compose"
)

REM 检查镜像是否存在
docker images read-later-server:latest | findstr "read-later-server" >nul
if errorlevel 1 (
    if not exist "read-later-server.tar" (
        echo 错误：找不到镜像文件！
        echo 请确保 read-later-server.tar 存在于当前目录
        pause
        exit /b 1
    )
    echo [1/2] 导入 Docker 镜像...
    docker load -i read-later-server.tar
    if errorlevel 1 (
        echo 镜像导入失败！
        pause
        exit /b 1
    )
) else (
    echo [1/2] 镜像已存在，跳过导入
)

echo.
echo [2/2] 启动服务...
%COMPOSE_CMD% -f docker-compose.offline.yml up -d

if errorlevel 1 (
    echo.
    echo 启动失败，请检查日志
    pause
    exit /b 1
)

echo.
echo ==========================================
echo 服务启动完成！
echo 访问地址：http://localhost:3000
echo 数据目录：./data
echo ==========================================
echo.
echo 常用命令：
echo   查看日志：%COMPOSE_CMD% -f docker-compose.offline.yml logs -f
echo   停止服务：%COMPOSE_CMD% -f docker-compose.offline.yml down
echo   重启服务：%COMPOSE_CMD% -f docker-compose.offline.yml restart
echo.

pause
