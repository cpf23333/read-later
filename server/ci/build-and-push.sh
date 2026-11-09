#!/bin/bash
# 构建并推送 CI 镜像脚本
# 用法: ./build-and-push.sh <仓库地址> [镜像名] [标签]
#
# 镜像源等构建参数从当前目录的 .env 文件读取
# 示例 .env：
#   BASE_IMAGE=your-registry/library/node:24
#   APT_REPO_DEBIAN=http://your-nexus/repository/debian-bookworm-proxy
#   NPM_REGISTRY=http://your-nexus/repository/npm-proxy/
#
# 示例:
#   ./build-and-push.sh your-registry readlater-ci latest

set -e

if [ -z "$1" ]; then
  echo "错误：必须指定仓库地址"
  echo "用法: ./build-and-push.sh <仓库地址> [镜像名] [标签]"
  exit 1
fi

REGISTRY="$1"
IMAGE_NAME="${2:-readlater-ci}"
TAG="${3:-latest}"

FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${TAG}"

echo "=== 构建 CI 镜像 ==="
echo "目标: ${FULL_IMAGE}"

cd "$(dirname "$0")"

# 检查 .env 文件
ENV_FILE="./.env"
if [ ! -f "$ENV_FILE" ]; then
  if [ -f "./.env.example" ]; then
    echo "首次运行，从 .env.example 创建 .env"
    cp ./.env.example ./.env
    echo "请编辑 .env 配置镜像源，然后重新运行本脚本"
    exit 0
  else
    echo "错误：找不到 .env 或 .env.example"
    exit 1
  fi
fi

# 加载 .env（runner 环境变量优先，不覆盖已存在的变量）
if [ -f ./.env ]; then
  while IFS='=' read -r key value; do
    # 跳过注释和空行
    [[ "$key" =~ ^# ]] && continue
    [[ -z "$key" ]] && continue
    # 去除 value 首尾空白（简单处理）
    value="$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    # 仅当环境变量未设置时才从 .env 读取
    if [ -z "${!key+x}" ] && [ -n "$value" ]; then
      export "$key=$value"
    fi
  done < ./.env
fi

# 拼装 build args
BUILD_ARGS=()
add_build_arg() {
  local key="$1"
  local default_value="${2:-}"
  local value="${!key:-$default_value}"
  if [ -n "$value" ]; then
    BUILD_ARGS+=("--build-arg" "${key}=${value}")
    echo "使用 build arg: ${key}=${value}"
  fi
}

add_build_arg BASE_IMAGE node:24
add_build_arg APT_REPO_DEBIAN
add_build_arg APT_REPO_SECURITY
add_build_arg NPM_REGISTRY
add_build_arg INSECURE_REGISTRIES

docker build "${BUILD_ARGS[@]}" -t "${FULL_IMAGE}" .

echo ""
echo "=== 登录仓库 ==="
if [ -n "${DOCKER_REGISTRY_PASSWORD}" ]; then
  echo "${DOCKER_REGISTRY_PASSWORD}" | docker login "${REGISTRY}" -u "${DOCKER_REGISTRY_USER:-}" --password-stdin
else
  docker login "${REGISTRY}"
fi

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
