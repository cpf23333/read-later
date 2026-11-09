@echo off
REM 镜像构建脚本 - 在有网环境运行

echo === 构建 read-later-server 镜像 ===

REM Dockerfile 需要项目根目录作为 build context
cd /d "%~dp0\.."

REM 基础镜像：优先读环境变量，其次 server\.env 的 BASE_IMAGE，最后默认 node:24-alpine
if not defined BASE_IMAGE if exist "server\.env" (
    for /f "usebackq tokens=1,* delims==" %%A in ("server\.env") do (
        if /i "%%A"=="BASE_IMAGE" if not defined BASE_IMAGE set "BASE_IMAGE=%%B"
    )
)
if not defined BASE_IMAGE set "BASE_IMAGE=node:24-alpine"

echo 使用基础镜像: %BASE_IMAGE%
echo.

REM 构建
docker build -f server/Dockerfile -t read-later-server:latest --build-arg "BASE_IMAGE=%BASE_IMAGE%" .
if %ERRORLEVEL% neq 0 (
    echo 构建失败！
    exit /b 1
)

REM 导出（可选，用于离线部署）
if "%1"=="--export" (
    echo === 导出镜像到 read-later-server.tar ===
    docker save read-later-server:latest -o read-later-server.tar
    echo 完成！镜像已导出到 read-later-server.tar
    echo.
    echo 无网环境部署步骤：
    echo   1. 复制 read-later-server.tar 到目标机器
    echo   2. 加载镜像：docker load -i read-later-server.tar
    echo   3. 运行：docker run -d -p 3000:3000 -e API_KEY=your_key -v ./data:/app/data read-later-server:latest
) else (
    echo 完成！
    echo.
    echo 如需导出镜像用于离线部署，请运行：build.bat --export
)
