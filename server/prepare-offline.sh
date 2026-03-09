#!/bin/bash
# 在有网络的机器上运行此脚本，准备离线部署包

set -e

echo "=========================================="
echo "ReadLater 离线部署包准备脚本"
echo "=========================================="
echo

# 创建临时目录
WORK_DIR=$(pwd)/.offline-build
mkdir -p $WORK_DIR
cd $WORK_DIR

# 允许通过环境变量指定镜像源（自动去除 https:// 前缀）
REGISTRY_PREFIX="${DOCKER_REGISTRY:-}"
# 去除可能的协议前缀和尾部斜杠
REGISTRY_PREFIX=$(echo "$REGISTRY_PREFIX" | sed 's|^https://||; s|^http://||; s|/$||')

# npm 镜像源
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"

if [ -n "$REGISTRY_PREFIX" ]; then
    echo "[1/4] 使用镜像源: $REGISTRY_PREFIX"
    echo "拉取基础镜像..."
    docker pull ${REGISTRY_PREFIX}/node:20-alpine
    # 重新打标签为官方名称
    docker tag ${REGISTRY_PREFIX}/node:20-alpine node:20-alpine
else
    echo "[1/4] 拉取基础镜像..."
    docker pull node:20-alpine
fi

echo
echo "[2/4] 构建应用镜像..."
echo "使用 npm 镜像: $NPM_REGISTRY"
cp ../Dockerfile ../package.json ../server.js ./

# 构建参数
BUILD_ARGS=""
if [ -n "$REGISTRY_PREFIX" ]; then
    BUILD_ARGS="$BUILD_ARGS --build-arg REGISTRY=${REGISTRY_PREFIX}/"
fi
if [ -n "$NPM_REGISTRY" ]; then
    BUILD_ARGS="$BUILD_ARGS --build-arg NPM_REGISTRY=$NPM_REGISTRY"
fi

docker build $BUILD_ARGS -t read-later-server:latest .

echo
echo "[3/4] 导出镜像..."
docker save node:20-alpine read-later-server:latest -o readlater-images.tar

echo
echo "[4/4] 打包部署文件..."
cp ../docker-compose.offline.yml ../start-offline.sh ../README-DEPLOY.md ./

# 创建最终部署包
tar czf ../readlater-offline.tar.gz \
  readlater-images.tar \
  docker-compose.offline.yml \
  start-offline.sh \
  README-DEPLOY.md

echo
echo "=========================================="
echo "离线部署包已生成：readlater-offline.tar.gz"
echo "=========================================="
echo
echo "请将此文件复制到 fnOS，然后解压运行："
echo "  tar xzf readlater-offline.tar.gz"
echo "  sudo bash start-offline.sh"
echo

# 清理
cd ..
rm -rf $WORK_DIR
