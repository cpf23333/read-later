# CI 部署专用 Dockerfile
# 由 pnpm deploy 输出的独立目录直接使用
FROM 192.168.1.100:5443/library/node:24-alpine

WORKDIR /app

# pnpm deploy 已包含 package.json / dist / node_modules（生产依赖）
COPY . .

# 创建数据目录
RUN mkdir -p /app/data
VOLUME ["/app/data"]

EXPOSE 3000

CMD ["node", "dist/index.js"]
