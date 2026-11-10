#!/usr/bin/env bash
# 构建并推送移动端 CI 镜像（readlater-android-ci）
#
# 用法：
#   ./build-and-push.sh [镜像版本] [--push-only|--build-only]
#
# 示例：
#   ./build-and-push.sh 3.38.10-r2
#   ./build-and-push.sh 3.38.10-r2 --push-only
#   ./build-and-push.sh 3.38.10-r2 --build-only
#
# 环境变量：
#   CI_REGISTRY      镜像仓库（mobile/ci/.env）
#   IMAGE_NAME       镜像名，默认 readlater-android-ci
#   IMAGE_VERSION    镜像版本（未传参数时使用；默认自动生成时间戳版本）
#   NODE_IMAGE       构建用 Node 镜像，默认 node:24-bookworm-slim
#   PUB_HOSTED_URL   pub 源，默认 https://pub.flutter-io.cn
#   PUSH_RETRIES     推送重试次数，默认 5

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

ENV_FILE="$ROOT/mobile/ci/.env"
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

VERSION=""
MODE="build-push"
for arg in "$@"; do
  case "$arg" in
    --push-only) MODE="push-only" ;;
    --build-only) MODE="build-only" ;;
    --help|-h)
      echo "Usage: $0 [image-version] [--push-only|--build-only]"
      exit 0
      ;;
    *)
      if [ -z "$VERSION" ]; then
        VERSION="$arg"
      else
        echo "未知参数: $arg" >&2
        exit 1
      fi
      ;;
  esac
done

VERSION="${VERSION:-${IMAGE_VERSION:-}}"
if [ -z "$VERSION" ]; then
  TS="$(date -u +%Y%m%d-%H%M)"
  VERSION="${FLUTTER_BASE_VERSION:-3.38.10}-${TS}"
fi
REGISTRY="${CI_REGISTRY:-}"
IMAGE_NAME="${IMAGE_NAME:-readlater-android-ci}"
NODE_IMAGE="${NODE_IMAGE:-node:24-bookworm-slim}"
PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"
SDK_IMAGE="${SDK_IMAGE:-}"
PUSH_RETRIES="${PUSH_RETRIES:-5}"

if [ -z "$REGISTRY" ]; then
  echo "错误：CI_REGISTRY 未设置（可写入 mobile/ci/.env）" >&2
  exit 1
fi
if [ -z "$SDK_IMAGE" ]; then
  echo "错误：SDK_IMAGE 未设置（可写入 mobile/ci/.env）" >&2
  exit 1
fi

FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${VERSION}"

echo "=== 构建移动端 CI 镜像 ==="
echo "目标: ${FULL_IMAGE}"
echo "模式: ${MODE}"
echo "IMAGE_VERSION: ${VERSION}"

if [ "$MODE" != "push-only" ]; then
  echo "NODE_IMAGE: ${NODE_IMAGE}"
  echo "PUB_HOSTED_URL: ${PUB_HOSTED_URL}"
  echo "SDK_IMAGE: ${SDK_IMAGE}"
  docker build \
    --build-arg "IMAGE_VERSION=${VERSION}" \
    --build-arg "NODE_IMAGE=${NODE_IMAGE}" \
    --build-arg "PUB_HOSTED_URL=${PUB_HOSTED_URL}" \
    --build-arg "SDK_IMAGE=${SDK_IMAGE}" \
    -f mobile/ci/Dockerfile \
    -t "${FULL_IMAGE}" \
    mobile
fi

if [ "$MODE" = "build-only" ]; then
  echo ""
  echo "=== 构建完成，跳过推送 ==="
  echo "镜像: ${FULL_IMAGE}"
  exit 0
fi

if ! docker image inspect "${FULL_IMAGE}" >/dev/null 2>&1; then
  echo "错误：本地不存在镜像 ${FULL_IMAGE}" >&2
  echo "请先不带 --push-only 运行一次构建。" >&2
  exit 1
fi

echo ""
echo "=== 推送镜像 ==="
attempt=0
while [ "$attempt" -lt "$PUSH_RETRIES" ]; do
  attempt=$((attempt + 1))
  echo "--- push attempt ${attempt}/${PUSH_RETRIES} ---"
  if docker push "${FULL_IMAGE}"; then
    echo ""
    echo "=== 完成 ==="
    echo "镜像: ${FULL_IMAGE}"
    cat <<EOF

Forgejo Variables:
  MOBILE_CI_IMAGE         = ${FULL_IMAGE}
  MOBILE_CI_IMAGE_VERSION = ${VERSION}

刷新 runner 的 dind:
  docker exec docker_dind docker rmi ${FULL_IMAGE} || true
  docker exec docker_dind docker pull ${FULL_IMAGE}

EOF
    exit 0
  fi
  echo "推送失败，10 秒后重试..." >&2
  sleep 10
done

echo "错误：推送 ${PUSH_RETRIES} 次仍失败" >&2
exit 1
