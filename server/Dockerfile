# 本地构建 Dockerfile
# 基于完整项目上下文，不跳过生命周期脚本
# 用法（在项目根目录执行）:
#   docker build -f server/Dockerfile -t read-later-server:latest .
#
# 基础镜像源示例（通过 --build-arg BASE_IMAGE=... 传入）：
#   - Docker Hub 官方：node:24-alpine
#   - 国内加速/私有仓库：your-registry/library/node:24-alpine
#
# 如果本地能访问私有仓库，也可以把 builder 阶段改为:
#   FROM your-registry/readlater-ci:latest AS builder
#   （可省去安装 pnpm / buildah / skopeo 的步骤）

ARG BASE_IMAGE=node:24-alpine

# ===== 构建阶段 =====
FROM ${BASE_IMAGE} AS builder

WORKDIR /app

# 如需更换 Alpine apk 源，可在此添加：
#   RUN sed -i 's|https://dl-cdn.alpinelinux.org/alpine|http://mirrors.aliyun.com/alpine|g' /etc/apk/repositories
#
# 安装编译工具（better-sqlite3 / sharp 需要）+ pnpm
RUN apk add --no-cache python3 make g++ vips-dev && \
    npm install -g pnpm@10.15.1

# 复制 workspace 配置（完整项目，extension 存在，wxt prepare 可正常执行）
# 使用 .npmrc* 通配符：存在 .npmrc 时复制，不存在也不报错
COPY .npmrc* pnpm-workspace.yaml package.json pnpm-lock.yaml ./
COPY extension/package.json extension/tsconfig.json extension/wxt.config.ts ./extension/
COPY extension/entrypoints ./extension/entrypoints
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
FROM ${BASE_IMAGE}

WORKDIR /app

# sharp 运行时依赖
RUN apk add --no-cache vips

COPY --from=builder /app/deploy/node_modules ./node_modules
COPY --from=builder /app/deploy/dist ./dist
COPY --from=builder /app/deploy/package.json .

RUN mkdir -p /app/data
VOLUME ["/app/data"]

EXPOSE 3000

CMD ["node", "dist/index.js"]
