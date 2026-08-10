# ReadLater Server 部署指南

## 方案一：联网部署（需 Docker Hub 访问）

如果你的服务器能访问 Docker Hub 或阿里云镜像：

```bash
cd server

# 修改 API_KEY（必须）
vim docker-compose.yml

# 启动
docker-compose up -d
```

---

## 方案二：完全离线部署（推荐）

适用于无外网环境（如内网 NAS）。

### 步骤 1：准备离线包（在有网络的机器上）

默认使用阿里云镜像源，无需额外配置：

```bash
cd server
./build-offline.sh
```

Windows:

```cmd
cd server
build-offline.bat
```

可选配置（环境变量）：

```bash
# 使用其他镜像源（覆盖默认阿里云）
DOCKER_REGISTRY=docker.xuanyuan.me ./build-offline.sh
```

输出：`readlater-offline.zip`

包含内容：

- `readlater-images.tar` 或 `read-later-server.tar` - Docker 镜像
- `docker-compose.offline.yml` - 部署配置
- `start-offline.sh/.bat` - 启动脚本
- `update-offline.sh/.bat` - 更新脚本
- `README-DEPLOY.md` - 部署说明

### 步骤 2：部署到目标服务器

```bash
# 1. 复制并解压
unzip readlater-offline.zip

# 2. 修改配置（重要！）
vim docker-compose.offline.yml

# 必须修改：
# - API_KEY: 设置鉴权密钥
# - volumes: 修改为实际数据目录
#
# 示例：
# environment:
#   - API_KEY=$(openssl rand -base64 32)
# volumes:
#   - /vol1/backup/readlater:/app/data

# 3. 启动（Linux/Mac）
./start-offline.sh

# 或启动（Windows）
start-offline.bat
```

### 步骤 3：验证

```bash
# 查看容器状态
docker ps | grep readlater

# 查看日志
docker logs readlater

# 测试 API
curl http://localhost:3000/api/health
```

---

## 离线更新

当有新版本时，无需重新配置：

### 1. 准备新的离线包

在有网络的机器上重新执行：

```bash
./prepare-offline.sh
```

### 2. 在服务器上更新

将新的 `read-later-server.tar` 复制到服务器：

```bash
# Linux/Mac
./update-offline.sh

# Windows
update-offline.bat
```

更新脚本会自动：

1. 加载新的 Docker 镜像
2. 停止并删除旧容器（数据保留）
3. 清理旧镜像
4. 启动新容器

---

## 目录结构

```
server/
├── Dockerfile                  # Docker 多阶段构建配置
├── docker-compose.yml          # 联网部署配置
├── docker-compose.offline.yml  # 离线部署配置
├── prepare-offline.sh          # 离线包准备脚本（需联网）
├── start-offline.sh            # 离线启动脚本（Linux/Mac）
├── start-offline.bat           # 离线启动脚本（Windows）
├── update-offline.sh           # 离线更新脚本（Linux/Mac）
├── update-offline.bat          # 离线更新脚本（Windows）
├── package.json
└── server.js
```

---

## 环境变量（必需）

| 变量       | 必需 | 说明         | 示例                      |
| ---------- | ---- | ------------ | ------------------------- |
| `API_KEY`  | ✅   | API 鉴权密钥 | `openssl rand -base64 32` |
| `PORT`     | ❌   | 服务端口     | `3000`                    |
| `DATA_DIR` | ❌   | 数据目录     | `/app/data`               |

---

## 常见问题

### 1. 找不到 docker compose 命令

脚本会自动检测 `docker compose`（新版）或 `docker-compose`（旧版）。

### 2. 数据持久化

务必修改 `docker-compose.offline.yml` 中的 volumes 为实际存储路径：

```yaml
volumes:
  - /vol1/backup/readlater:/app/data
```

### 3. 端口冲突

修改 `docker-compose.offline.yml`：

```yaml
ports:
  - '3001:3000' # 主机 3001 映射到容器 3000
```

### 4. API Key 未配置

服务端启动必须配置 `API_KEY`，否则拒绝启动。生成命令：

```bash
openssl rand -base64 32
```

---

## 安全配置

### API Key 鉴权（必须）

1. **生成密钥**：

   ```bash
   openssl rand -base64 32
   ```

2. **配置服务端**：
   编辑 `docker-compose.offline.yml`：

   ```yaml
   environment:
     - API_KEY=your-generated-api-key
   ```

3. **配置扩展端**：
   在浏览器扩展设置页面 → 服务器 → API Key 中填写相同密钥

4. **验证**：
   ```bash
   # 未带 Key 应返回 401
   curl http://localhost:3000/api/links

   # 带 Key 应正常返回
   curl -H "Authorization: Bearer your-api-key" http://localhost:3000/api/links
   ```

> **注意**：Health 检查接口 (`/api/health`) 始终公开，用于连接测试。
