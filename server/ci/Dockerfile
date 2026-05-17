# CI 镜像：基于 Alpine + buildah + skopeo + pnpm
# 构建命令: docker build -t readlater-ci:latest .
FROM swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/node:24-alpine

# 安装容器构建工具 + 原生编译工具（better-sqlite3 需要）+ 网络工具
RUN apk add --no-cache buildah skopeo netavark aardvark-dns iptables ip6tables python3 make g++ curl jq

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
