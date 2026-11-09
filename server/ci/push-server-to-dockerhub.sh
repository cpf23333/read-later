#!/bin/bash
# 构建 read-later-server 镜像并推送到 Docker Hub
# 用法: ./push-server-to-dockerhub.sh [标签]
#
# 示例:
#   ./push-server-to-dockerhub.sh latest
#   ./push-server-to-dockerhub.sh v1.0.0

set -e

DOCKERHUB_USER="cpf23333"
TAG="${1:-latest}"

IMAGE_NAME="${DOCKERHUB_USER}/read-later-server"
FULL_IMAGE="${IMAGE_NAME}:${TAG}"
LATEST_IMAGE="${IMAGE_NAME}:latest"

echo "=== 构建 read-later-server 镜像 ==="
echo "目标: ${FULL_IMAGE}"

cd "$(dirname "$0")/../.."

docker build -f server/Dockerfile -t "${FULL_IMAGE}" .

# 如果 tag 不是 latest，同时打上 latest 标签
if [ "$TAG" != "latest" ]; then
  echo ""
  echo "=== 额外标记 latest ==="
  docker tag "${FULL_IMAGE}" "${LATEST_IMAGE}"
fi

echo ""
echo "=== 登录 Docker Hub ==="
docker login

echo ""
echo "=== 推送镜像 ==="
docker push "${FULL_IMAGE}"

if [ "$TAG" != "latest" ]; then
  docker push "${LATEST_IMAGE}"
fi

echo ""
echo "=== 完成 ==="
echo "镜像已推送: ${FULL_IMAGE}"
if [ "$TAG" != "latest" ]; then
  echo "镜像已推送: ${LATEST_IMAGE}"
fi
