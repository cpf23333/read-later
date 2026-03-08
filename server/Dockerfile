# 支持自定义镜像源 ?Dockerfile
# 使用方法 ?
#   docker build --build-arg REGISTRY=docker.xuanyuan.me/library/ \
#                --build-arg NPM_REGISTRY=https://registry.npmmirror.com \
#                -t read-later-server .
# 注意：REGISTRY 不要 ?https:// 协议前缀

ARG REGISTRY="docker.xuanyuan.me/"
FROM ${REGISTRY}node:20-alpine

WORKDIR /app

# 安装 Python 和构建工具（better-sqlite3 需要编译）
RUN apk add --no-cache python3 make g++

# 支持自定 ?npm 镜像 ?
ARG NPM_REGISTRY="https://registry.npmmirror.com"

# 复制并安装依 ?
COPY package.json .
RUN npm install --registry=${NPM_REGISTRY}

# 复制代码
COPY server.js .

# 创建数据目录
RUN mkdir -p /app/data

# 数据 ?
VOLUME ["/app/data"]

EXPOSE 3000

CMD ["node", "server.js"]
