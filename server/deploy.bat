@echo off
chcp 65001 >nul
REM ReadLater 服务器一键部署脚本（Windows）

setlocal enabledelayedexpansion

set SCRIPT_DIR=%~dp0
for %%i in ("%SCRIPT_DIR%..") do set PROJECT_ROOT=%%~fi
set COMPOSE_FILE=%PROJECT_ROOT%\server\docker-compose.yml
set ENV_FILE=%SCRIPT_DIR%.env

REM 检测 docker compose 命令
docker compose version >nul 2>&1
if %errorlevel% == 0 (
  set COMPOSE_CMD=docker compose
) else (
  docker-compose version >nul 2>&1
  if %errorlevel% == 0 (
    set COMPOSE_CMD=docker-compose
  ) else (
    echo [错误] 未检测到 docker compose 命令，请先安装 Docker。
    exit /b 1
  )
)

REM 检查 .env 文件
if not exist "%ENV_FILE%" (
  echo [首次部署] 正在创建 .env 配置文件...
  if exist "%SCRIPT_DIR%.env.example" (
    copy "%SCRIPT_DIR%.env.example" "%ENV_FILE%" >nul
  ) else (
    echo [错误] 找不到 %SCRIPT_DIR%.env.example 模板文件。
    exit /b 1
  )
  echo [提示] 请编辑 %ENV_FILE% 设置 API_KEY，然后重新运行本脚本。
  exit /b 0
)

REM 加载 .env 到当前环境
for /f "usebackq eol=# tokens=1* delims==" %%a in ("%ENV_FILE%") do (
  set "%%a=%%b"
)

REM 检查 API_KEY 是否已设置
if "%API_KEY%"=="" (
  echo [错误] 未在 %ENV_FILE% 中设置 API_KEY。
  echo [提示] 请先生成密钥：openssl rand -base64 32
  echo [提示] 然后编辑 %ENV_FILE% 填写 API_KEY。
  exit /b 1
)

echo [信息] 开始部署 ReadLater 服务器...

REM 创建数据目录（路径基于 docker-compose.yml 所在目录解析）
for %%i in ("%COMPOSE_FILE%..") do set COMPOSE_DIR=%%~fi
if not defined DATA_PATH set DATA_PATH=./data
set "DATA_PATH=%DATA_PATH:/=\%"
echo %DATA_PATH% | findstr /B /R "[A-Za-z]:\\ \"" >nul
if errorlevel 1 set "DATA_PATH=%COMPOSE_DIR%\%DATA_PATH%"
if not exist "%DATA_PATH%" mkdir "%DATA_PATH%"

cd /d "%PROJECT_ROOT%"

REM 根据 DOCKER_REGISTRY 决定是否拉取预构建镜像
if defined DOCKER_REGISTRY (
  echo [信息] 使用预构建镜像：%DOCKER_REGISTRY%/read-later-server:latest
  %COMPOSE_CMD% -f "%COMPOSE_FILE%" --env-file "%ENV_FILE%" pull
) else (
  echo [信息] 本地构建镜像...
)

%COMPOSE_CMD% -f "%COMPOSE_FILE%" --env-file "%ENV_FILE%" up -d

echo [信息] 部署完成！
echo.
echo 服务状态：
%COMPOSE_CMD% -f "%COMPOSE_FILE%" --env-file "%ENV_FILE%" ps

echo.
echo [信息] 健康检查：
if not defined PORT set PORT=3000
timeout /t 2 /nobreak >nul 2>&1
curl -s "http://localhost:%PORT%/api/health" 2>nul || echo 健康检查失败，请查看日志

echo.
echo [提示] 查看日志：%COMPOSE_CMD% -f %COMPOSE_FILE% --env-file %ENV_FILE% logs -f
