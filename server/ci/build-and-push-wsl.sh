#!/bin/bash
# WSL 环境构建脚本
# 在 WSL 终端中执行

set -e

# Nexus 配置（端口路由模式 - 推荐）
# 在 Nexus 中配置 HTTP 端口为 8083
NEXUS_HOST="192.168.1.3:8083"
IMAGE_NAME="readlater-ci"
TAG="latest"
FULL_IMAGE="${NEXUS_HOST}/${IMAGE_NAME}:${TAG}"

echo "=== WSL 环境构建 CI 镜像 ==="
echo "目标: ${FULL_IMAGE}"

cd "$(dirname "$0")"

echo ""
echo "=== 构建镜像 ==="
docker build -t "${FULL_IMAGE}" .

echo ""
echo ""
echo "=== 配置 Docker 允许非 HTTPS 仓库 ==="
echo "{ \"insecure-registries\": [\"${NEXUS_HOST}\"] }" | sudo tee /etc/docker/daemon.json > /dev/null
sudo systemctl restart docker
sleep 3

echo "=== 登录 Nexus ==="
read -p "输入 Nexus 用户名: " USERNAME
read -s -p "输入 Nexus 密码: " PASSWORD
echo ""
echo "${PASSWORD}" | docker login "${NEXUS_HOST}" -u "${USERNAME}" --password-stdin

echo ""
echo "=== 推送镜像 ==="
docker push "${FULL_IMAGE}"

echo ""
echo "=== 完成 ==="
echo "镜像已推送: ${FULL_IMAGE}"
