# 多阶段构建 - 减小镜像体积
# 使用方法：
#   docker build --build-arg REGISTRY=docker.xuanyuan.me/library/ \
#                --build-arg NPM_REGISTRY=https://registry.npmmirror.com \
#                -t read-later-server .
# 注意：REGISTRY 不要加 https:// 协议前缀

ARG REGISTRY="docker.xuanyuan.me/"

# ===== 阶段 1：构建 =====
FROM ${REGISTRY}node:20-alpine AS builder

WORKDIR /app

# 安装 Python 和编译工具（better-sqlite3 需要编译）
RUN apk add --no-cache python3 make g++

# 支持自定义 npm 镜像
ARG NPM_REGISTRY="https://registry.npmmirror.com"

# 复制并安装依赖
COPY package.json .
RUN npm install --registry=${NPM_REGISTRY}

# ===== 阶段 2：运行 =====
FROM ${REGISTRY}node:20-alpine

WORKDIR /app

# 只复制必要文件（编译后的二进制模块已包含在 node_modules 中）
COPY --from=builder /app/node_modules ./node_modules
COPY package.json .
COPY server.js .

# 创建数据目录
RUN mkdir -p /app/data

# 数据卷
VOLUME ["/app/data"]

EXPOSE 3000

CMD ["node", "server.js"]
