# ReadLater Server 部署指南

## 方案一：使用国内镜像源（需联网）

如果 fnOS 能访问阿里云镜像仓库：

```bash
cd server
docker-compose up -d
```

Dockerfile 已配置使用 `registry.cn-hangzhou.aliyuncs.com/nodejs/node:20-alpine`

---

## 方案二：完全离线部署（推荐）

### 步骤 1：在有网络的机器上构建镜像

在 Windows 上：
```cmd
cd server
build-offline.bat
```

在 Linux/Mac 上：
```bash
cd server
chmod +x build-offline.sh
./build-offline.sh
```

输出：`readlater-offline.zip`

### 步骤 2：复制到 fnOS

将 `readlater-offline.zip` 复制到 fnOS 的任意目录

### 步骤 3：在 fnOS 上部署

```bash
# 解压
unzip readlater-offline.zip

# 修改数据目录（重要！）
vim docker-compose.offline.yml
# 将 volumes 改为：
# - /vol1/backup/readlater:/app/data

# 启动（Linux）
chmod +x start-offline.sh
./start-offline.sh

# 或启动（Windows）
start-offline.bat
```

### 步骤 4：验证

```bash
# 查看容器状态
docker ps | grep readlater

# 查看日志
docker logs readlater

# 测试 API
curl http://localhost:3000/api/health
```

---

## 目录结构

```
server/
├── Dockerfile                  # 标准构建（使用阿里云源）
├── Dockerfile.offline          # 离线构建（使用本地 node_modules）
├── docker-compose.yml          # 标准部署
├── docker-compose.offline.yml  # 离线部署
├── build-offline.bat           # Windows 离线打包脚本
├── build-offline.sh            # Linux 离线打包脚本
├── start-offline.bat           # Windows 离线启动脚本
├── start-offline.sh            # Linux 离线启动脚本
├── package.json
└── server.js
```

---

## 常见问题

### 1. 镜像拉取失败
检查 fnOS Docker 是否配置了镜像加速器，或直接使用方案二离线部署。

### 2. better-sqlite3 编译失败
确保基础镜像包含 python3、make、g++ 编译工具。

### 3. 数据持久化
务必修改 `docker-compose.offline.yml` 中的 volumes 路径为 fnOS 实际存储路径，例如：
```yaml
volumes:
  - /vol1/backup/readlater:/app/data
```

### 4. 端口冲突
如果 3000 端口被占用，修改 `docker-compose.offline.yml`：
```yaml
ports:
  - "3001:3000"  # 主机 3001 映射到容器 3000
```

---

## 安全配置

### API Key 鉴权（必须）

服务端必须配置 API Key，否则无法启动。

1. **生成随机密钥**（Linux/macOS）：
   ```bash
   openssl rand -base64 32
   ```

2. **配置服务端**：
   编辑 `docker-compose.yml`（或 `docker-compose.offline.yml`），修改 `API_KEY`：
   ```yaml
   environment:
     - API_KEY=your-generated-api-key
   ```

3. **配置扩展端**：
   在浏览器扩展的设置页面 → 服务器 → API Key 中填写相同的密钥

4. **验证**：
   ```bash
   # 未带 Key 应返回 401
   curl http://localhost:3000/api/links
   
   # 带 Key 应正常返回
   curl -H "Authorization: Bearer your-api-key" http://localhost:3000/api/links
   ```

> **注意**：Health 检查接口 (`/api/health`) 始终公开，用于连接测试。
