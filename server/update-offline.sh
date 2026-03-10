#!/bin/bash

echo "=========================================="
echo "ReadLater Server 离线更新脚本"
echo "=========================================="
echo

# 检测 docker compose 命令（兼容新版和旧版）
if docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
elif docker-compose version &>/dev/null; then
    COMPOSE_CMD="docker-compose"
else
    echo "❌ 错误：未找到 docker compose 命令"
    echo "请确保 Docker 和 Docker Compose 已安装"
    exit 1
fi

# 检查镜像文件是否存在
if [ ! -f "read-later-server.tar" ]; then
    echo "❌ 错误：read-later-server.tar 文件不存在"
    echo "请确保已将新的镜像文件复制到当前目录"
    exit 1
fi

echo "[1/4] 正在加载新镜像..."
docker load -i read-later-server.tar

if [ $? -ne 0 ]; then
    echo "❌ 镜像加载失败！"
    exit 1
fi

echo
echo "[2/4] 正在停止旧容器..."
$COMPOSE_CMD -f docker-compose.offline.yml down

echo
echo "[3/4] 正在清理旧镜像..."
docker image prune -f

echo
echo "[4/4] 正在启动新容器..."
$COMPOSE_CMD -f docker-compose.offline.yml up -d

if [ $? -eq 0 ]; then
    echo
    echo "=========================================="
    echo "✅ 更新成功！"
    echo "=========================================="
    echo
    echo "查看状态: $COMPOSE_CMD -f docker-compose.offline.yml ps"
    echo "查看日志: $COMPOSE_CMD -f docker-compose.offline.yml logs -f"
else
    echo
    echo "=========================================="
    echo "❌ 启动失败，请检查日志"
    echo "=========================================="
fi
