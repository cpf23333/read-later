#!/usr/bin/env bash
# 构建并推送 Android SDK 基础镜像（readlater-android-sdk）
#
# 用法：
#   ./build-sdk.sh [sdk-version]
#
# 示例：
#   ./build-sdk.sh 3.38.10-r1
#
# 环境变量：
#   CI_REGISTRY       镜像仓库（mobile/ci/.env）
#   SDK_IMAGE_NAME    镜像名，默认 readlater-android-sdk
#   SDK_VERSION       未传参数时使用，默认 3.38.10-r1
#   FLUTTER_IMAGE     Flutter 基础镜像，默认 ghcr.io/cirruslabs/flutter:3.38.10
#   PUSH_RETRIES      推送重试次数，默认 5

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

SDK_VERSION="${1:-${SDK_VERSION:-}}"
if [ -z "$SDK_VERSION" ]; then
  TS="$(date -u +%Y%m%d-%H%M)"
  SDK_VERSION="${FLUTTER_BASE_VERSION:-3.38.10}-${TS}"
fi
REGISTRY="${CI_REGISTRY:-}"
SDK_IMAGE_NAME="${SDK_IMAGE_NAME:-readlater-android-sdk}"
FLUTTER_IMAGE="${FLUTTER_IMAGE:-ghcr.io/cirruslabs/flutter:3.38.10}"
SDK_TEST_BASE_URL="${SDK_TEST_BASE_URL:-}"
PUSH_RETRIES="${PUSH_RETRIES:-5}"

if [ -z "$REGISTRY" ]; then
  echo "错误：CI_REGISTRY 未设置（可写入 mobile/ci/.env）" >&2
  exit 1
fi
if [ -z "$SDK_TEST_BASE_URL" ]; then
  echo "错误：SDK_TEST_BASE_URL 未设置（可写入 mobile/ci/.env）" >&2
  exit 1
fi

FULL_IMAGE="${REGISTRY}/${SDK_IMAGE_NAME}:${SDK_VERSION}"

echo "=== 构建 Android SDK 基础镜像 ==="
echo "目标: ${FULL_IMAGE}"
echo "FLUTTER_IMAGE: ${FLUTTER_IMAGE}"
echo "SDK_TEST_BASE_URL: ${SDK_TEST_BASE_URL}"

docker build \
  --build-arg "FLUTTER_IMAGE=${FLUTTER_IMAGE}" \
  --build-arg "SDK_TEST_BASE_URL=${SDK_TEST_BASE_URL}" \
  --build-arg "SDK_REVISION=${SDK_VERSION}" \
  -f mobile/ci/Dockerfile.sdk \
  -t "${FULL_IMAGE}" \
  mobile/ci

attempt=0
while [ "$attempt" -lt "$PUSH_RETRIES" ]; do
  attempt=$((attempt + 1))
  echo ""
  echo "=== push attempt ${attempt}/${PUSH_RETRIES} ==="
  if docker push "${FULL_IMAGE}"; then
    cat <<EOF

=== 完成 ===
SDK 基础镜像: ${FULL_IMAGE}

下一步构建 CI 镜像时传入：
  SDK_IMAGE=${FULL_IMAGE}

例如：
  SDK_IMAGE=${FULL_IMAGE} ./mobile/ci/build-and-push.sh 3.38.10-r2

如果 SDK 版本变了，同步修改 mobile/ci/Dockerfile 里的默认 SDK_IMAGE。
EOF
    exit 0
  fi
  echo "推送失败，10 秒后重试..." >&2
  sleep 10
done

echo "错误：推送 ${PUSH_RETRIES} 次仍失败" >&2
exit 1
