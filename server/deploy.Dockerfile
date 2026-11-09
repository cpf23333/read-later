# CI 部署专用 Dockerfile
# 由 pnpm deploy 输出的独立目录直接使用
#
# 基础镜像源示例（通过 --build-arg BASE_IMAGE=... 传入）：
#   - Docker Hub 官方：node:24-alpine
#   - 国内加速/私有仓库：your-registry/library/node:24-alpine
ARG BASE_IMAGE=node:24-alpine
FROM ${BASE_IMAGE}

WORKDIR /app

# pnpm deploy 已包含 package.json / dist / node_modules（生产依赖）
COPY . .

# 创建数据目录
RUN mkdir -p /app/data
VOLUME ["/app/data"]

EXPOSE 3000

CMD ["node", "dist/index.js"]
