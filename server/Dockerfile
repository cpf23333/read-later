# 标准构建 Dockerfile
# 在有网环境构建，导出镜像后可在无网环境运行

FROM node:20-alpine AS builder

WORKDIR /app

# 安装编译工具（better-sqlite3 需要）
RUN apk add --no-cache python3 make g++

# 复制依赖配置并安装（包括 devDependencies 用于构建）
COPY package.json ./
RUN npm install

# 复制源码并构建
COPY . .
RUN npm run build

# 重新安装仅生产依赖（清理 devDependencies）
RUN rm -rf node_modules && npm install --production

# ===== 运行阶段 =====
FROM node:20-alpine

WORKDIR /app

# 只复制生产依赖和构建产物
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY package.json .

# 创建数据目录
RUN mkdir -p /app/data
VOLUME ["/app/data"]

EXPOSE 3000

CMD ["node", "dist/index.js"]
