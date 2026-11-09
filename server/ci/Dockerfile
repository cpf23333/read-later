# CI 镜像：基于 Debian + buildah + skopeo + pnpm
# 构建命令:
#   docker build -t readlater-ci:latest -f server/ci/Dockerfile server/ci
#
# 镜像源示例：
#   BASE_IMAGE:
#     - node:24                           # Docker Hub 官方
#     - your-registry/library/node:24 # 私有仓库/加速服务
#
#   APT_REPO_DEBIAN / APT_REPO_SECURITY:
#     - http://deb.debian.org/debian                   # Debian 官方
#     - http://security.debian.org/debian-security     # Debian 官方 security
#     - http://mirrors.aliyun.com/debian               # 阿里云
#     - http://your-nexus/repository/debian-bookworm-proxy         # Nexus
#     - http://your-nexus/repository/debian-security-bookworm-proxy # Nexus
#
#   NPM_REGISTRY:
#     - https://registry.npmjs.org              # npm 官方
#     - https://registry.npmmirror.com          # 国内镜像
#     - http://your-nexus/repository/npm-proxy/ # Nexus
#
#   INSECURE_REGISTRIES:
#     - your-registry:port,another-registry:port
#
# 镜像源等参数也可通过 build-and-push.sh / build-and-push.bat 自动读取 .env 传入：
#   1. 复制 .env.example 为 .env
#   2. 编辑 .env 填写镜像源
#   3. ./build-and-push.sh your-registry readlater-ci latest

ARG BASE_IMAGE=node:24
FROM ${BASE_IMAGE}

ARG APT_REPO_DEBIAN=http://deb.debian.org/debian
ARG APT_REPO_SECURITY=http://security.debian.org/debian-security

# 换 apt 源（默认 Debian 官方，可通过 build arg 覆盖为私有 proxy）
RUN if [ "${APT_REPO_DEBIAN}" != "http://deb.debian.org/debian" ] || [ "${APT_REPO_SECURITY}" != "http://security.debian.org/debian-security" ]; then \
      sed -i \
        -e "s|http://deb.debian.org/debian-security|${APT_REPO_SECURITY}|g" \
        -e "s|http://security.debian.org/debian-security|${APT_REPO_SECURITY}|g" \
        -e "s|http://deb.debian.org/debian|${APT_REPO_DEBIAN}|g" \
        /etc/apt/sources.list.d/debian.sources; \
    fi

ARG NPM_REGISTRY=https://registry.npmjs.org

# npm 源（可通过 build arg 覆盖）+ 国内镜像加速 prebuild/node-gyp
ENV NPM_CONFIG_REGISTRY=${NPM_REGISTRY}
ENV npm_config_disturl=https://npmmirror.com/mirrors/node
ENV npm_config_prebuild_install_mirror=https://registry.npmmirror.com/-/binary/prebuild-install

# 安装容器构建工具 + 原生编译工具（better-sqlite3 需要）+ 网络工具 + Docker CLI
RUN apt-get update && apt-get install -y \
    buildah skopeo docker.io curl jq python3 make g++ \
    && rm -rf /var/lib/apt/lists/*

ARG INSECURE_REGISTRIES=""

# 配置 Buildah / Skopeo 允许访问 HTTP 私有仓库
RUN if [ -n "${INSECURE_REGISTRIES}" ]; then \
      mkdir -p /etc/containers && \
      { \
        echo 'unqualified-search-registries = ["docker.io"]'; \
        echo ''; \
        IFS=','; for reg in ${INSECURE_REGISTRIES}; do \
          echo "[[registry]]"; \
          echo "prefix = \"${reg}\""; \
          echo "location = \"${reg}\""; \
          echo "insecure = true"; \
          echo ""; \
        done; \
      } > /etc/containers/registries.conf; \
    fi

# 嵌套容器环境下强制使用 vfs 存储驱动
ENV STORAGE_DRIVER=vfs

# 安装 pnpm
RUN npm install -g pnpm

# 验证安装
RUN node --version && \
    pnpm --version && \
    buildah --version && \
    skopeo --version

# 设置工作目录
WORKDIR /workspace
