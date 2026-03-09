#!/bin/bash

echo "=========================================="
echo "ReadLater Server 离线镜像构建脚本"
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
rm -f readlater-offline.zip
zip readlater-offline.zip docker-compose.offline.yml read-later-server.tar start-offline.sh

echo
echo "=========================================="
echo "构建完成！"
echo "输出文件：readlater-offline.zip"
echo "=========================================="
echo
echo "部署步骤："
echo "1. 将 readlater-offline.zip 复制到 fnOS"
echo "2. 解压后运行 ./start-offline.sh"
echo
