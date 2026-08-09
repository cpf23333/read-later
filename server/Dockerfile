# 本地构建 Dockerfile
# 基于完整项目上下文，不跳过生命周期脚本
# 用法（在项目根目录执行）:
#   docker build -f server/Dockerfile -t read-later-server:latest .
#
# 如果本地能访问私有仓库，也可以把 builder 阶段改为:
#   FROM 192.168.1.100:8083/readlater-ci:latest AS builder
#   （可省去安装 pnpm / buildah / skopeo 的步骤）

# ===== 构建阶段 =====
FROM 192.168.1.100:8083/library/node:24-alpine AS builder

WORKDIR /app

# 安装编译工具（better-sqlite3 需要）+ pnpm
RUN apk add --no-cache python3 make g++ && \
    npm install -g pnpm

# 复制 workspace 配置（完整项目，entrypoints 存在，wxt prepare 可正常执行）
COPY pnpm-workspace.yaml package.json pnpm-lock.yaml ./
COPY server/package.json ./server/

# 安装依赖（完整项目上下文，生命周期脚本正常执行）
RUN pnpm install --frozen-lockfile

# 复制 server 源码并构建
COPY server ./server
WORKDIR /app/server
RUN pnpm build

# 导出 server 到独立目录
WORKDIR /app
RUN pnpm deploy --filter=read-later-server --prod /app/deploy

# ===== 运行阶段 =====
FROM 192.168.1.100:8083/library/node:24-alpine

WORKDIR /app

COPY --from=builder /app/deploy/node_modules ./node_modules
COPY --from=builder /app/deploy/dist ./dist
COPY --from=builder /app/deploy/package.json .

RUN mkdir -p /app/data
VOLUME ["/app/data"]

EXPOSE 3000

CMD ["node", "dist/index.js"]
