#!/bin/bash

echo "=========================================="
echo "ReadLater Server 离线启动脚本"
echo "=========================================="
echo

# 检查镜像是否存在
if ! docker images read-later-server:latest | grep -q "read-later-server"; then
    echo "[1/2] 导入 Docker 镜像..."
    if [ -f "read-later-server.tar" ]; then
        docker load -i read-later-server.tar
    else
        echo "错误：找不到镜像文件！"
        echo "请确保 read-later-server.tar 存在于当前目录"
        exit 1
    fi
    if [ $? -ne 0 ]; then
        echo "镜像导入失败！"
        exit 1
    fi
else
    echo "[1/2] 镜像已存在，跳过导入"
fi

# 检测 docker compose 命令（兼容新版和旧版）
if docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
elif docker-compose version &>/dev/null; then
    COMPOSE_CMD="docker-compose"
else
    echo "错误：未找到 docker compose 命令"
    echo "请确保 Docker 和 Docker Compose 已安装"
    exit 1
fi

echo
echo "[2/2] 启动服务..."
$COMPOSE_CMD -f docker-compose.offline.yml up -d

echo
echo "=========================================="
echo "服务启动完成！"
echo "访问地址：http://localhost:3000"
echo "数据目录：./data"
echo "=========================================="
echo
echo "常用命令："
echo "  查看日志：$COMPOSE_CMD -f docker-compose.offline.yml logs -f"
echo "  停止服务：$COMPOSE_CMD -f docker-compose.offline.yml down"
echo "  重启服务：$COMPOSE_CMD -f docker-compose.offline.yml restart"
echo
