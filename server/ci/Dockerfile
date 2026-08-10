# CI 镜像：基于 Debian + buildah + skopeo + pnpm
# 构建命令: docker build -t readlater-ci:latest .
FROM 192.168.1.100:5443/library/node:24

# 换 Nexus apt proxy（保留 Debian 官方签名验证）
RUN sed -i \
    -e 's|http://deb.debian.org/debian-security|http://192.168.1.100:8081/repository/debian-security-bookworm-proxy|g' \
    -e 's|http://security.debian.org/debian-security|http://192.168.1.100:8081/repository/debian-security-bookworm-proxy|g' \
    -e 's|http://deb.debian.org/debian|http://192.168.1.100:8081/repository/debian-bookworm-proxy|g' \
    /etc/apt/sources.list.d/debian.sources

# 使用 Nexus npm proxy 安装依赖 + 国内镜像加速 prebuild/node-gyp
ENV NPM_CONFIG_REGISTRY=http://192.168.1.100:8081/repository/npm-proxy/
ENV npm_config_disturl=https://npmmirror.com/mirrors/node
ENV npm_config_prebuild_install_mirror=https://registry.npmmirror.com/-/binary/prebuild-install

# 安装容器构建工具 + 原生编译工具（better-sqlite3 需要）+ 网络工具 + Docker CLI
RUN apt-get update && apt-get install -y \
    buildah skopeo docker.io curl jq python3 make g++ \
    && rm -rf /var/lib/apt/lists/* 

# 配置 Buildah / Skopeo 允许访问 HTTP 私有仓库
RUN mkdir -p /etc/containers && \
    printf '%s\n' \
      '[[registry]]' \
      'prefix = "192.168.1.100:8083"' \
      'location = "192.168.1.100:8083"' \
      'insecure = true' \
      '' \
      '[[registry]]' \
      'prefix = "192.168.1.100:5443"' \
      'location = "192.168.1.100:5443"' \
      'insecure = true' \
      > /etc/containers/registries.conf

# 嵌套容器环境下强制使用 vfs 存储驱动
ENV STORAGE_DRIVER=vfs

# 安装 pnpm（走 Nexus npm proxy）
RUN npm install -g pnpm

# 验证安装
RUN node --version && \
    pnpm --version && \
    buildah --version && \
    skopeo --version

# 设置工作目录
WORKDIR /workspace
