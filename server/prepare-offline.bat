@echo off
chcp 65001 >nul
echo ==========================================
echo ReadLater 离线部署包准备脚本
echo ==========================================
echo.

set WORK_DIR=%TEMP%\readlater-offline-build

if exist "%WORK_DIR%" rmdir /s /q "%WORK_DIR%"
mkdir "%WORK_DIR%"
cd /d "%WORK_DIR%"

echo [1/4] 拉取基础镜像...
docker pull node:20-alpine
if errorlevel 1 (
    echo 拉取镜像失败！请检查网络连接
    pause
    exit /b 1
)

echo.
echo [2/4] 构建应用镜像...
copy "%~dp0Dockerfile" .
copy "%~dp0package.json" .
copy "%~dp0server.js" .
docker build -t read-later-server:latest .
if errorlevel 1 (
    echo 构建失败！
    pause
    exit /b 1
)

echo.
echo [3/4] 导出镜像...
docker save node:20-alpine read-later-server:latest -o readlater-images.tar

echo.
echo [4/4] 打包部署文件...
copy "%~dp0docker-compose.offline.yml" .
copy "%~dp0start-offline.bat" .
copy "%~dp0README-DEPLOY.md" .
copy "%~dp0start-offline.sh" .

powershell -Command "Compress-Archive -Path 'readlater-images.tar','docker-compose.offline.yml','start-offline.bat','start-offline.sh','README-DEPLOY.md' -DestinationPath '%~dp0readlater-offline.zip'"

echo.
echo ==========================================
echo 离线部署包已生成：%~dp0readlater-offline.zip
echo ==========================================
echo.
echo 请将此文件复制到 fnOS，然后解压运行：
echo   unzip readlater-offline.zip
echo   sudo bash start-offline.sh
echo.

cd /d "%~dp0"
rmdir /s /q "%WORK_DIR%"

pause