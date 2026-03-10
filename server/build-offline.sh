#!/bin/bash
# 离线部署包构建脚本
# 在有网络的机器上运行，打包所有 Docker 镜像和部署脚本
# 输出包含基础镜像，目标机器无需任何外网访问

set -e

echo "=========================================="
echo "ReadLater 离线部署包构建脚本"
echo "=========================================="
echo

# 配置
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"
# Docker 镜像源（可修改为你自己的镜像源，需要包含库路径如 library/）
DOCKER_REGISTRY="${DOCKER_REGISTRY:-docker.xuanyuan.me/library/}"

# 构建镜像完整名称
if [ -n "$DOCKER_REGISTRY" ]; then
    # 去除可能的协议前缀和尾部斜杠
    REGISTRY_CLEAN=$(echo "$DOCKER_REGISTRY" | sed 's|^https://||; s|^http://||; s|/$||')
    BASE_IMAGE="${REGISTRY_CLEAN}/node:20-alpine"
    BUILD_ARG_REGISTRY="--build-arg REGISTRY=${REGISTRY_CLEAN}/"
    echo "Docker 镜像源: $REGISTRY_CLEAN"
else
    BASE_IMAGE="node:20-alpine"
    BUILD_ARG_REGISTRY=""
fi
echo "npm 镜像: $NPM_REGISTRY"
echo

# 步骤 1：检查/拉取基础镜像
echo "[1/4] 检查基础镜像..."
if docker image inspect node:20-alpine &>/dev/null; then
    echo "  本地已存在 node:20-alpine，跳过拉取"
else
    echo "  拉取 $BASE_IMAGE..."
    docker pull "$BASE_IMAGE"
    # 重新打标签为官方名称，方便 Dockerfile 使用
    docker tag "$BASE_IMAGE" node:20-alpine
fi
echo

# 步骤 2：构建应用镜像
echo "[2/4] 构建应用镜像..."
docker build \
  $BUILD_ARG_REGISTRY \
  --build-arg NPM_REGISTRY="$NPM_REGISTRY" \
  -t read-later-server:latest .

if [ $? -ne 0 ]; then
    echo "❌ 构建失败！请检查 Docker 是否正常运行"
    exit 1
fi

# 步骤 3：导出镜像
echo
echo "[3/4] 导出镜像（基础镜像 + 应用镜像）..."
docker save node:20-alpine read-later-server:latest -o read-later-server.tar

# 步骤 4：打包
echo
echo "[4/4] 打包部署文件..."

rm -f readlater-offline.zip
zip readlater-offline.zip \
  docker-compose.offline.yml \
  read-later-server.tar \
  start-offline.sh \
  start-offline.bat \
  update-offline.sh \
  update-offline.bat \
  README-DEPLOY.md

echo
echo "=========================================="
echo "✅ 离线部署包已生成：readlater-offline.zip"
echo "   read-later-server.tar 已保留（可单独用于更新）"
echo "=========================================="
echo
echo "包含内容："
echo "  - read-later-server.tar   (Docker 镜像：包含 node:20-alpine 基础镜像)"
echo "  - docker-compose.offline.yml"
echo "  - start-offline.sh / .bat   (启动脚本)"
echo "  - update-offline.sh / .bat  (更新脚本)"
echo "  - README-DEPLOY.md"
echo
echo "说明：完全离线，目标机器无需任何外网访问"
echo
echo "部署步骤："
echo "  1. 将 readlater-offline.zip 复制到目标服务器"
echo "  2. 解压：unzip readlater-offline.zip"
echo "  3. 启动：./start-offline.sh (Linux) 或 start-offline.bat (Windows)"
echo
echo "更新步骤："
echo "  1. 重新运行此脚本生成新包"
echo "  2. 将新的 read-later-server.tar 复制到服务器"
echo "  3. 执行：./update-offline.sh (Linux) 或 update-offline.bat (Windows)"
echo
