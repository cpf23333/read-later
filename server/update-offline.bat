@echo off
chcp 65001 >nul
echo ==========================================
echo ReadLater Server 离线更新脚本
echo ==========================================
echo.

REM 检测 docker compose 命令（兼容新版和旧版）
docker compose version >nul 2>&1
if errorlevel 1 (
    docker-compose version >nul 2>&1
    if errorlevel 1 (
        echo ❌ 错误：未找到 docker compose 命令
        echo 请确保 Docker 和 Docker Compose 已安装
        pause
        exit /b 1
    ) else (
        set "COMPOSE_CMD=docker-compose"
    )
) else (
    set "COMPOSE_CMD=docker compose"
)

REM 检查镜像文件是否存在
if not exist "read-later-server.tar" (
    echo ❌ 错误：read-later-server.tar 文件不存在
    echo 请确保已将新的镜像文件复制到当前目录
    pause
    exit /b 1
)

echo [1/4] 正在加载新镜像...
docker load -i read-later-server.tar

if errorlevel 1 (
    echo ❌ 镜像加载失败！
    pause
    exit /b 1
)

echo.
echo [2/4] 正在停止旧容器...
%COMPOSE_CMD% -f docker-compose.offline.yml down

echo.
echo [3/4] 正在清理旧镜像...
docker image prune -f

echo.
echo [4/4] 正在启动新容器...
%COMPOSE_CMD% -f docker-compose.offline.yml up -d

if errorlevel 1 (
    echo.
    echo ==========================================
    echo ❌ 启动失败，请检查日志
    echo ==========================================
    pause
    exit /b 1
)

echo.
echo ==========================================
echo ✅ 更新成功！
echo ==========================================
echo.
echo 查看状态: %COMPOSE_CMD% -f docker-compose.offline.yml ps
echo 查看日志: %COMPOSE_CMD% -f docker-compose.offline.yml logs -f
echo.

pause
