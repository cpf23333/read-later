#!/bin/bash
# 构建并推送 CI 镜像脚本
# 用法: ./build-and-push.sh [仓库地址] [镜像名] [标签] [alpine代理源]
#
# Nexus 示例:
#   ./build-and-push.sh 192.168.1.100:8083 readlater-ci latest https://nexus.example.com/repository/alpine-proxy
#

set -e

REGISTRY="${1:-192.168.1.100:8083}"
IMAGE_NAME="${2:-readlater-ci}"
TAG="${3:-latest}"
ALPINE_REPO_URL="${4:-}"

FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${TAG}"

echo "=== 构建 CI 镜像 ==="
echo "目标: ${FULL_IMAGE}"

cd "$(dirname "$0")"

BUILD_ARGS=()
if [ -n "${ALPINE_REPO_URL}" ]; then
  BUILD_ARGS+=("--build-arg" "ALPINE_REPO_URL=${ALPINE_REPO_URL}")
fi

docker build "${BUILD_ARGS[@]}" -t "${FULL_IMAGE}" .

echo ""
echo "=== 登录 Nexus (端口 8083) ==="
docker login 192.168.1.100:8083

echo ""
echo "=== 推送镜像 ==="
docker push "${FULL_IMAGE}"

echo ""
echo "=== 完成 ==="
echo "镜像已推送: ${FULL_IMAGE}"
echo ""
echo "请在 Forgejo 项目设置中添加 Secrets:"
echo "  DOCKER_REGISTRY_USER     - Docker 仓库用户名"
echo "  DOCKER_REGISTRY_PASSWORD - Docker 仓库密码"
