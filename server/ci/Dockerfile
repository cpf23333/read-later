# 自定义 CI 镜像：包含 buildah + Node.js + skopeo
# 构建命令: docker build -t readlater-ci:latest .
FROM quay.io/buildah/stable:latest

# 安装 Node.js 和其他工具
RUN dnf install -y nodejs skopeo && \
    dnf clean all && \
    rm -rf /var/cache/dnf/*

# 验证安装
RUN node --version && \
    npm --version && \
    buildah --version && \
    skopeo --version

# 设置工作目录
WORKDIR /workspace
