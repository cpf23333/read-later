# ReadLater - 稍后再看 项目指南

## 项目概述

一个浏览器扩展，用于收藏和管理链接，支持自动截图、图片提取和服务器同步。

## 技术栈

- **框架**: WXT (浏览器扩展开发框架)
- **前端**: Vue 3 + TypeScript
- **样式**: 原生 CSS (Scoped)
- **存储**: 服务器 SQLite 数据库（通过 HTTP API + Bearer Token 鉴权）
- **服务器**: Express + SQLite (server/)
- **构建**: Vite

## 项目结构

```
.
├── entrypoints/           # 扩展入口点
│   ├── background.ts      # 后台脚本（右键菜单、消息处理）
│   ├── content.ts         # 内容脚本（页面交互）
│   ├── popup/App.vue      # 弹出窗口
│   ├── options/App.vue    # 设置页面
│   └── link-manager/App.vue # 链接管理页面
├── utils/                 # 工具模块
│   ├── storage.ts         # 类型定义
│   ├── apiStorage.ts      # 服务器 API 调用
│   ├── hybridStorage.ts   # 统一存储接口
│   └── imageExtractor.ts  # 图片提取逻辑
├── server/                # 后端服务器
│   ├── server.js          # Express + SQLite 服务
│   ├── Dockerfile         # Docker 多阶段构建
│   ├── docker-compose.yml # Docker Compose 配置
│   ├── docker-compose.offline.yml  # 离线部署配置
│   ├── build-offline.sh   # 完全离线包构建脚本（Linux/Mac）
│   ├── build-offline.bat  # 完全离线包构建脚本（Windows）
│   ├── prepare-deploy.sh  # 联网部署包准备脚本（Linux/Mac，体积小）
│   ├── prepare-deploy.bat # 联网部署包准备脚本（Windows，体积小）
│   ├── start-offline.sh   # 离线启动脚本（Linux/Mac）
│   ├── start-offline.bat  # 离线启动脚本（Windows）
│   ├── update-offline.sh  # 离线更新脚本（Linux/Mac）
│   └── update-offline.bat # 离线更新脚本（Windows）
├── components/            # 共享组件
└── assets/                # 静态资源
```

## 核心功能模块

### 1. 链接收藏方式
- **右键菜单**: 在任意链接上右键选择"收好链接"
- **Popup按钮**: 点击扩展图标，选择"收好当前页面"
- **自动提取**: 页面截图、附近图片、页面标题

### 2. 图片处理流程
```
扩展提取图片
    ↓
[可选] Blob URL → base64 转换 (imageExtractor.ts)
    ↓
addLink() → apiAddLink() → POST /api/links (发送 base64)
    ↓
服务器 processImage() 处理
    ↓
├─ data:image/* → saveBase64ToFile() 保存
├─ http(s)://   → downloadImage() 下载保存
└─ /images/*    → 直接返回路径
    ↓
数据库存储文件路径
    ↓
GET /api/links 返回完整 URL
```

### 3. 回收站机制
- 删除链接时软删除，数据移到 `trash` 表
- 图片文件移动到 `images/deleted/` 目录（保持原文件名）
- 还原时移回 `images/` 目录
- 永久删除时删除文件

### 4. 数据存储
- **纯服务器存储**: 所有数据直接存到 SQLite
- **图片存储**: 服务器文件系统，`/images/` 和 `/images/deleted/`
- **路径格式**: 数据库存相对路径 `/images/xxx.jpg`，前端拼接完整 URL

## API 鉴权

所有 API 请求（除 `/api/health` 外）必须通过 Bearer Token 鉴权：

```http
Authorization: Bearer <API_KEY>
```

- 服务端启动时必须配置 `API_KEY` 环境变量，否则拒绝启动
- 扩展端在设置页面配置相同的 API Key
- 未携带或错误的 Key 返回 401
- 静态图片访问 (`/images/*`) 无需鉴权

生成随机密钥：
```bash
openssl rand -base64 32
```

## API 端点

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | /api/health | 健康检查（无需鉴权） |
| GET | /api/links | 获取链接列表 |
| POST | /api/links | 添加链接（支持 base64/URL/路径） |
| DELETE | /api/links/:id | 删除链接（移入回收站） |
| POST | /api/links/batch | 批量添加 |
| GET | /api/search | 搜索链接 |
| GET | /api/trash | 获取回收站 |
| POST | /api/trash/:id/restore | 还原链接 |
| DELETE | /api/trash/:id | 永久删除 |
| GET | /api/stats | 获取统计 |
| POST | /api/upload | 上传图片（保留兼容） |

## 关键代码位置

### 图片提取 (utils/imageExtractor.ts)
- `extractNearbyImage()` - 主提取函数
- `imageToBase64()` - 转换 blob/URL 为 base64
- `defaultImageExtractor()` - 默认提取策略
- `executeCustomExtractor()` - 执行自定义 JS

### 后台脚本 (entrypoints/background.ts)
- `handleMessage()` - 消息处理（CAPTURE_TAB, FETCH_TITLE 等）
- `captureTab()` - 获取页面截图
- `fetchPageTitle()` - 获取页面标题
- 右键菜单点击处理

### 服务器 (server/server.js)
- `processImage()` - 处理图片数据（base64/URL/路径）
- `saveBase64ToFile()` - 保存 base64 为文件
- `downloadImage()` - 下载网络图片
- `DELETE /api/links/:id` - 删除时移动图片到 deleted
- `POST /api/trash/:id/restore` - 还原时移回图片

### Popup (entrypoints/popup/App.vue)
- `saveCurrentPage()` - 保存当前页面
- 发送 `CAPTURE_TAB` 消息获取截图
- 发送 `FETCH_TITLE` 获取标题

## 调试方法

### 查看日志位置
1. **内容脚本**: 网页 F12 → Console
2. **Background**: 扩展管理 → 详情 → Inspect views: service worker
3. **Popup**: 右键扩展图标 → 检查弹出窗口
4. **服务器**: 服务器终端输出

### 关键日志标记
```
[ReadLater]        - background/content 日志
[Popup]            - popup 日志
[apiAddLink]       - API 发送日志
[Server]           - 服务器接收日志
[processImage]     - 图片处理日志
[saveBase64ToFile] - 文件保存日志
```

### 开发模式
```bash
pnpm dev    # 开启 sourcemap，保留 console
pnpm build  # 生产构建，压缩代码，移除 console
```

## 图片显示优先级

链接列表和回收站中，图片显示优先级：
1. nearbyImage（链接附近图片）
2. screenshot（页面截图）
3. 无图片（显示占位）

## 已知限制

1. **Blob URL**: 必须在内容脚本中转换为 base64 才能发送给服务器
2. **权限**: `activeTab` 权限只在用户交互时有效
3. **截图**: `captureVisibleTab` 只能捕获当前窗口可见区域

## 注意事项

1. **IndexedDB 已移除**: 现在是纯服务器存储
2. **图片自动处理**: 扩展发送 base64，服务器保存文件
3. **回收站图片**: 删除时自动移动到 deleted 目录
4. **路径处理**: 数据库存相对路径，前端拼接 baseUrl

## 服务器部署

### 方案一：联网部署
```bash
cd server
docker-compose up -d
```

### 方案二：完全离线部署（推荐）

适用于无外网环境（如内网 NAS）：

**步骤 1：在有网络的机器上构建离线包**
```bash
cd server
./build-offline.sh
```

脚本默认使用阿里云镜像源，无需额外配置。如需使用其他镜像源：
```bash
DOCKER_REGISTRY=your.mirror.com ./build-offline.sh
```

### 方案三：联网部署包（体积小）

适用于部署机器能访问 Docker Hub 或镜像源的场景：

```bash
cd server
./prepare-deploy.sh  # 输出 readlater-deploy.zip（~80MB，仅含应用镜像）
```

**步骤 2：复制到目标服务器**
```bash
# 解压
unzip readlater-offline.zip

# 修改数据目录（重要！）
vim docker-compose.offline.yml
# volumes:
#   - /your/data/path:/app/data

# 启动（Linux/Mac）
./start-offline.sh

# 或启动（Windows）
start-offline.bat
```

**步骤 3：更新（有新版时）**
```bash
# 1. 在新机器上重新执行 prepare-offline.sh 生成新包
# 2. 复制 readlater-images.tar 到服务器
# 3. 执行更新
./update-offline.sh  # Linux/Mac
# 或
update-offline.bat   # Windows
```

离线包包含：
- `readlater-images.tar` - Docker 镜像（node:20-alpine + read-later-server）
- `docker-compose.offline.yml` - 部署配置
- `start-offline.sh/.bat` - 启动脚本
- `update-offline.sh/.bat` - 更新脚本

### 环境变量（必需）
| 变量 | 说明 | 示例 |
|------|------|------|
| `API_KEY` | API 鉴权密钥（必须） | `openssl rand -base64 32` |
| `PORT` | 服务端口 | `3000` |
| `DATA_DIR` | 数据目录 | `/app/data` |

## 开发注意事项

### 文件编码规范
- **Shell 脚本** (`.sh`): UTF-8 无 BOM, LF 换行
- **Batch 脚本** (`.bat`): UTF-8 无 BOM, CRLF 换行
- **代码文件**: UTF-8 无 BOM

### Docker 多阶段构建
```dockerfile
# 阶段 1：构建（含编译工具）
FROM node:20-alpine AS builder
RUN apk add --no-cache python3 make g++
RUN npm install

# 阶段 2：运行（仅运行时文件）
FROM node:20-alpine
COPY --from=builder /app/node_modules ./node_modules
```
镜像体积：~200MB → ~80MB

## 相关文件

- [FEATURES.md](./FEATURES.md) - 功能清单
- [server/README-DEPLOY.md](./server/README-DEPLOY.md) - 服务器部署指南
- [server/SECURITY.md](./server/SECURITY.md) - 安全配置说明
