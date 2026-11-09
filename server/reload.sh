#!/bin/bash
# 重新加载镜像并重启服务（用于更新）

set -e

TAR_FILE="read-later-server.tar"

if [ ! -f "$TAR_FILE" ]; then
    echo "错误：找不到 $TAR_FILE"
    echo "请将新的镜像包复制到当前目录"
    exit 1
fi

echo "=== 停止现有服务 ==="
docker-compose -f docker-compose.yml down 2>/dev/null || docker stop readlater 2>/dev/null || true

echo "=== 加载新镜像 ==="
docker load -i "$TAR_FILE"

echo "=== 启动服务 ==="
docker-compose -f docker-compose.yml --env-file .env up -d --no-build

echo "=== 完成 ==="
docker ps | grep readlater
