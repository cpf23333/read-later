#!/bin/bash

echo "=========================================="
echo "ReadLater Server 离线启动脚本"
echo "=========================================="
echo

# 检查镜像是否存在
if ! docker images read-later-server:latest | grep -q "read-later-server"; then
    echo "[1/2] 导入 Docker 镜像..."
    # 优先加载完整包（包含基础镜像）
    if [ -f "readlater-images.tar" ]; then
        docker load -i readlater-images.tar
    elif [ -f "read-later-server.tar" ]; then
        docker load -i read-later-server.tar
    else
        echo "错误：找不到镜像文件！"
        echo "请确保 readlater-images.tar 或 read-later-server.tar 存在"
        exit 1
    fi
    if [ $? -ne 0 ]; then
        echo "镜像导入失败！"
        exit 1
    fi
else
    echo "[1/2] 镜像已存在，跳过导入"
fi

echo
echo "[2/2] 启动服务..."
docker-compose -f docker-compose.offline.yml up -d

echo
echo "=========================================="
echo "服务启动完成！"
echo "访问地址：http://localhost:3000"
echo "数据目录：./data"
echo "=========================================="
echo
echo "常用命令："
echo "  查看日志：docker-compose -f docker-compose.offline.yml logs -f"
echo "  停止服务：docker-compose -f docker-compose.offline.yml down"
echo "  重启服务：docker-compose -f docker-compose.offline.yml restart"
echo
