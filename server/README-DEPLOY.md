# ReadLater Server 部署指南

> 本文档面向最终用户，介绍如何部署 ReadLater 自建后端服务器。

> **版本说明**：当前服务器版本为 **0.9.0（预发布）**。0.9.x 阶段主要用于测试和收集反馈，正式发布前建议定期备份数据。

## 前置要求

- 已安装 [Docker](https://docs.docker.com/get-docker/) 和 Docker Compose
- 服务器至少有 1GB 可用内存
- 开放一个端口供扩展访问（默认 3000）

---

## 方案一：一键部署（推荐）

最简单的部署方式，适合大多数用户。

### Linux / Mac

```bash
# 1. 下载部署文件
curl -L -o readlater-deploy.zip https://your-domain/readlater-deploy.zip
unzip readlater-deploy.zip
cd readlater-server

# 或者从源码目录进入
cd server

# 2. 运行部署脚本
./deploy.sh
```

首次运行会创建 `.env` 文件并提示你设置 `API_KEY`。

### Windows

```powershell
# 下载并解压部署包后，进入 server 目录
cd server

# 运行部署脚本
.\deploy.bat
```

### 设置 API Key

脚本会生成 `.env` 文件，请编辑它：

```bash
# 生成随机密钥
openssl rand -base64 32

# 编辑 .env
vim .env
```

```env
API_KEY=your-generated-api-key-here
```

保存后再次运行 `./deploy.sh` 或 `.\deploy.bat` 即可启动。

### 使用 Docker Hub 预构建镜像（可选）

如果你不想本地构建镜像，可以直接使用 Docker Hub 上的预构建镜像：

```bash
# 编辑 .env
DOCKER_REGISTRY=cpf23333
```

然后运行 `./deploy.sh` 或 `.\deploy.bat`，脚本会自动拉取 `cpf23333/read-later-server:latest` 并启动。

> 注意：预构建镜像可能略晚于源码更新，如需使用最新代码，请保持 `DOCKER_REGISTRY` 留空以启用本地构建。

---

## 方案二：手动 Docker Compose 部署

如果你不想使用一键脚本，可以手动操作。

### 1. 创建 .env 文件

```bash
cd server

# 复制示例（如果没有 deploy.sh 生成的 .env）
cat > .env <<EOF
API_KEY=$(openssl rand -base64 32)
PORT=3000
DATA_PATH=./data
ALLOWED_ORIGINS=*
MAX_IMAGE_SIZE_MB=10
BACKUP_INTERVAL_HOURS=24
BACKUP_KEEP_COUNT=7
EOF
```

### 2. 启动服务

```bash
docker compose --env-file .env up -d --build
```

### 3. 验证

```bash
# 查看容器状态
docker compose ps

# 查看日志
docker compose logs -f

# 测试 API
curl http://localhost:3000/api/health
```

---

## 方案三：完全离线部署

适用于无外网环境（如内网 NAS）。

### 步骤 1：导出镜像（在有网络的机器上）

```bash
cd server
./build.sh --export
```

Windows:

```cmd
cd server
build.bat --export
```

输出：`read-later-server.tar`

### 步骤 2：部署到目标服务器

```bash
# 1. 复制文件到服务器
cp read-later-server.tar /path/to/server/

# 2. 进入 server 目录
cd /path/to/server

# 3. 创建 .env（如果还没有）
cat > .env <<EOF
API_KEY=$(openssl rand -base64 32)
PORT=3000
DATA_PATH=./data
EOF

# 4. 加载镜像并启动
./reload.sh
```

Windows:

```cmd
cd D:\path\to\server
reload.bat
```

`reload.sh` / `reload.bat` 会自动加载 `read-later-server.tar` 并使用 `docker-compose.yml` 启动服务（带 `--no-build`，避免尝试构建）。

### 步骤 3：验证

```bash
# 查看容器状态
docker ps | grep readlater

# 查看日志
docker compose logs -f

# 测试 API
curl http://localhost:3000/api/health
```

---

## 离线更新

当有新版本时，无需重新配置：

### 1. 导出新的镜像

在有网络的机器上重新执行：

```bash
cd server
./build.sh --export
```

### 2. 在服务器上更新

将新的 `read-later-server.tar` 复制到服务器 `server/` 目录，然后运行：

```bash
# Linux/Mac
./reload.sh

# Windows
reload.bat
```

`reload.sh` / `reload.bat` 会自动：

1. 加载新的 Docker 镜像
2. 停止并删除旧容器（数据保留）
3. 启动新容器

---

## 环境变量说明

| 变量 | 必需 | 说明 | 示例 |
| --- | --- | --- | --- |
| `API_KEY` | ✅ | API 鉴权密钥，扩展端需填写相同密钥 | `openssl rand -base64 32` |
| `PORT` | ❌ | 主机服务端口 | `3000` |
| `DATA_PATH` | ❌ | 主机数据目录 | `./data` |
| `DOCKER_REGISTRY` | ❌ | 预构建镜像仓库前缀，留空则本地构建 | `cpf23333`（Docker Hub）|
| `BASE_IMAGE` | ❌ | 基础镜像源，留空则使用 `node:24-alpine` | `your-registry/library/node:24-alpine` |
| `ALLOWED_ORIGINS` | ❌ | CORS 来源，生产环境建议限制 | `*` |
| `MAX_IMAGE_SIZE_MB` | ❌ | 单张图片大小限制 | `10` |
| `BACKUP_INTERVAL_HOURS` | ❌ | 数据库自动备份间隔，0 关闭 | `24` |
| `BACKUP_KEEP_COUNT` | ❌ | 保留备份数量 | `7` |
| `LOG_LEVEL` | ❌ | 日志级别（debug/info/warn/error） | `info` |

---

## 镜像源配置

如果你处于内网环境或访问公网较慢，可以配置私有镜像源。

### 基础镜像源

编辑 `.env`：

```env
# Docker Hub 官方
BASE_IMAGE=node:24-alpine

# 私有镜像仓库 / 加速服务
BASE_IMAGE=your-registry/library/node:24-alpine

# 国内加速示例（可用性以实际网络为准）
BASE_IMAGE=docker.m.daocloud.io/library/node:24-alpine
```

> `build.sh` / `build.bat` 会读取 `server/.env` 的 `BASE_IMAGE` 并传给 `docker build --build-arg`；`docker compose` 也会自动读取同一值。
> 使用 HTTP 私有仓库时，需要在 Docker 配置中添加 `insecure-registries`。

### npm 源

编辑项目根目录 `.npmrc`：

```ini
# npm 官方
registry=https://registry.npmjs.org

# 国内镜像
registry=https://registry.npmmirror.com

# 私有 Nexus
registry=http://your-nexus/repository/npm-proxy/
```

### CI 镜像源

构建 `readlater-ci` 镜像时，推荐通过 `server/ci/.env` 配置镜像源：

```bash
cd server/ci

# 复制模板并编辑
cp .env.example .env
vim .env

# 构建并推送
./build-and-push.sh your-registry readlater-ci latest
```

`.env` 中可配置：

```env
BASE_IMAGE=your-registry/library/node:24
APT_REPO_DEBIAN=http://your-nexus/repository/debian-bookworm-proxy
APT_REPO_SECURITY=http://your-nexus/repository/debian-security-bookworm-proxy
NPM_REGISTRY=http://your-nexus/repository/npm-proxy/
INSECURE_REGISTRIES=your-registry:port,another-registry:port
```

---

## 安全配置

### API Key 鉴权（必须）

1. **生成密钥**：

   ```bash
   openssl rand -base64 32
   ```

2. **配置服务端**：
   编辑 `.env` 或 `docker-compose.yml`：

   ```env
   API_KEY=your-generated-api-key
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

---

## 常见问题

### 1. 找不到 docker compose 命令

脚本会自动检测 `docker compose`（新版）或 `docker-compose`（旧版）。

### 2. 数据持久化

务必修改 `.env` 中的 `DATA_PATH` 为实际存储路径：

```env
DATA_PATH=/vol1/backup/readlater
```

### 3. 端口冲突

修改 `.env`：

```env
PORT=3001
```

### 4. 镜像拉取 / 构建失败

如果报 `load metadata for docker.io/library/node:24-alpine`，说明拉不到 Docker Hub 基础镜像。在 `server/.env` 设置可用的基础镜像源（国内加速或私有仓库）后重新执行 `build.bat` / `build.sh`：

```env
BASE_IMAGE=docker.m.daocloud.io/library/node:24-alpine
```

若 `apk add` 阶段偶发报错（如 `gdk-pixbuf` trigger error），通常是 Alpine 源网络波动，清理构建缓存后重试：

```bash
docker builder prune -f
```

使用预构建镜像但无法访问时，检查 `DOCKER_REGISTRY`，或清空后切换回本地构建模式。

---

## 目录结构

```
server/
├── Dockerfile                  # Docker 多阶段构建配置
├── docker-compose.yml          # 部署配置（在线/离线通用）
├── deploy.sh                   # 一键部署脚本（Linux/Mac）
├── deploy.bat                  # 一键部署脚本（Windows）
├── build.sh                    # 镜像构建/导出脚本（Linux/Mac）
├── build.bat                   # 镜像构建/导出脚本（Windows）
├── reload.sh                   # 离线镜像加载/更新脚本（Linux/Mac）
├── reload.bat                  # 离线镜像加载/更新脚本（Windows）
├── src/                        # 服务器源码
└── package.json
```
