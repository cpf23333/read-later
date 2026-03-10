#!/bin/bash

# 联网部署包准备脚本
# 输出仅包含应用镜像，目标机器需要能拉取 node:20-alpine 基础镜像

echo "=========================================="
echo "ReadLater 联网部署包准备脚本"
echo "=========================================="
echo

# 构建镜像
echo "[1/3] 正在构建 Docker 镜像..."
docker build -t read-later-server:latest .

if [ $? -ne 0 ]; then
    echo "构建失败！请检查 Docker 是否正常运行"
    exit 1
fi

echo
echo "[2/3] 正在导出镜像为 tar 包..."
docker save read-later-server:latest -o read-later-server.tar

echo
echo "[3/3] 打包部署文件..."
rm -f readlater-deploy.zip
zip readlater-deploy.zip docker-compose.offline.yml read-later-server.tar start-offline.sh start-offline.bat update-offline.sh update-offline.bat README-DEPLOY.md

echo
echo "=========================================="
echo "构建完成！"
echo "输出文件：readlater-deploy.zip"
echo "说明：仅包含应用镜像，目标机器需要能拉取 node:20-alpine"
echo "=========================================="
echo
echo "包含内容："
echo "  - read-later-server.tar   (Docker 镜像：仅 read-later-server)"
echo "  - docker-compose.offline.yml"
echo "  - start-offline.sh / .bat   (启动脚本)"
echo "  - update-offline.sh / .bat  (更新脚本)"
echo "  - README-DEPLOY.md"
echo
echo "部署步骤："
echo "  1. 将 readlater-deploy.zip 复制到目标服务器"
echo "  2. 解压：unzip readlater-deploy.zip"
echo "  3. 启动：./start-offline.sh (Linux) 或 start-offline.bat (Windows)"
echo
