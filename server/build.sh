#!/bin/bash
# 镜像构建脚本 - 在有网环境运行

set -e

echo "=== 构建 read-later-server 镜像 ==="

# Dockerfile 需要项目根目录作为 build context
cd "$(dirname "$0")/.."

# 构建
docker build -f server/Dockerfile -t read-later-server:latest .

# 导出（可选，用于离线部署）
if [ "$1" = "--export" ]; then
    echo "=== 导出镜像到 read-later-server.tar ==="
    docker save read-later-server:latest -o read-later-server.tar
    echo "完成！镜像已导出到 read-later-server.tar"
    echo ""
    echo "无网环境部署步骤："
    echo "  1. 复制 read-later-server.tar 到目标机器"
    echo "  2. 加载镜像：docker load -i read-later-server.tar"
    echo "  3. 运行：docker run -d -p 3000:3000 -e API_KEY=your_key -v ./data:/app/data read-later-server:latest"
else
    echo "完成！"
    echo ""
    echo "如需导出镜像用于离线部署，请运行：./build.sh --export"
fi
