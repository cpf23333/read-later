# 标准构建 Dockerfile
# 基于 pnpm deploy 的 workspace 多阶段构建

# ===== 构建阶段 =====
FROM node:20-alpine AS builder

WORKDIR /app

# 安装编译工具（better-sqlite3 需要）+ pnpm
RUN apk add --no-cache python3 make g++ && \
    npm install -g pnpm

# 先复制 workspace 配置（利用缓存，这些文件不常变）
COPY pnpm-workspace.yaml package.json pnpm-lock.yaml ./
COPY server/package.json ./server/

# 安装依赖（严格锁定版本）
RUN pnpm install --frozen-lockfile

# 再复制 server 源码并构建
COPY server ./server
WORKDIR /app/server
RUN pnpm build

# 导出 server 包到独立目录（自动只保留生产依赖，解除 workspace 硬链接依赖）
WORKDIR /app
RUN pnpm deploy --filter=read-later-server --prod /app/deploy

# ===== 运行阶段 =====
FROM node:20-alpine

WORKDIR /app

# deploy 出来的目录是自包含的，直接复制即可
COPY --from=builder /app/deploy/node_modules ./node_modules
COPY --from=builder /app/deploy/dist ./dist
COPY --from=builder /app/deploy/package.json .

# 创建数据目录
RUN mkdir -p /app/data
VOLUME ["/app/data"]

EXPOSE 3000

CMD ["node", "dist/index.js"]
