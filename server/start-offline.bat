@echo off
chcp 65001 >nul
echo ==========================================
echo ReadLater Server 离线启动脚本
echo ==========================================
echo.

docker images read-later-server:latest | findstr "read-later-server" >nul
if errorlevel 1 (
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
docker-compose -f docker-compose.offline.yml up -d

echo.
echo ==========================================
echo 服务启动完成！
echo 访问地址：http://localhost:3000
echo 数据目录：./data
echo ==========================================
echo.
echo 常用命令：
echo   查看日志：docker-compose -f docker-compose.offline.yml logs -f
echo   停止服务：docker-compose -f docker-compose.offline.yml down
echo   重启服务：docker-compose -f docker-compose.offline.yml restart
echo.
pause