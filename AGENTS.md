# ReadLater - 稍后再看 项目指南

## 项目概述

一个浏览器扩展，用于收藏和管理链接，支持自动截图、图片提取和服务器同步。

## 技术栈

- **框架**: WXT (浏览器扩展开发框架)
- **前端**: Vue 3 + TypeScript
- **样式**: 原生 CSS (Scoped)
- **存储**: 服务器 SQLite 数据库（通过 HTTP API + Bearer Token 鉴权）
- **服务器**: Hono + TypeScript + SQLite (server/)
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
│   ├── imageExtractor.ts  # 图片提取逻辑
│   └── imageUrl.ts        # 图片 URL 处理（缩略图）
├── server/                # 后端服务器
│   ├── src/               # TypeScript 源代码
│   │   ├── index.ts       # 主入口
│   │   ├── routes/        # 路由定义
│   │   ├── middleware/    # 中间件（鉴权、限流）
│   │   ├── utils/         # 工具函数（数据库、图片处理、URL 标准化）
│   │   └── types/         # 类型定义
│   ├── dist/              # 编译后的 JavaScript
│   ├── Dockerfile         # Docker 多阶段构建
│   ├── docker-compose.yml # Docker Compose 配置（在线/离线通用）
│   ├── deploy.sh          # 一键部署脚本（Linux/Mac）
│   ├── deploy.bat         # 一键部署脚本（Windows）
│   ├── build.sh           # 镜像构建/导出脚本（Linux/Mac）
│   ├── build.bat          # 镜像构建/导出脚本（Windows）
│   ├── reload.sh          # 离线镜像加载/更新脚本（Linux/Mac）
│   └── reload.bat         # 离线镜像加载/更新脚本（Windows）
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
├─ data:image/* → saveBase64ToFile() 保存原图
├─ http(s)://   → downloadImage() 下载保存原图
└─ /images/*    → 直接返回路径
    ↓
sharp 生成缩略图到 /images/thumbs/
    ↓
数据库存储原图路径
    ↓
GET /api/links 返回完整 URL（列表优先使用缩略图）
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

| 方法   | 路径                       | 说明                                   |
| ------ | -------------------------- | -------------------------------------- |
| GET    | /api/health                | 健康检查（无需鉴权）                   |
| GET    | /api/links                 | 获取链接列表                           |
| POST   | /api/links                 | 添加链接（支持 base64/URL/路径）       |
| DELETE | /api/links/:id             | 删除链接（移入回收站）                 |
| PATCH  | /api/links/:id             | 更新标题/图片（重新收藏时刷新）        |
| POST   | /api/links/batch           | 批量添加                               |
| POST   | /api/links/batch-delete    | 批量删除（移入回收站）                 |
| GET    | /api/links/exists          | 检查链接是否已存在（标准化 URL）       |
| POST   | /api/links/check-batch     | 批量检查链接是否已存在                 |
| GET    | /api/search                | 搜索链接（多关键字 AND 匹配）          |
| GET    | /api/trash                 | 获取回收站                             |
| POST   | /api/trash/:id/restore     | 还原链接                               |
| DELETE | /api/trash/:id             | 永久删除                               |
| POST   | /api/trash/batch-restore   | 批量还原回收站项目                     |
| POST   | /api/trash/batch-delete    | 批量永久删除回收站项目                 |
| GET    | /api/stats                 | 获取统计                               |
| GET    | /api/sites                 | 站点列表（不含回收站）                 |
| POST   | /api/sites                 | 新增站点（origin 去重，回收站中则恢复） |
| DELETE | /api/sites/:id             | 删除站点（软删除进回收站）             |
| GET    | /api/sites/trash           | 回收站站点                             |
| POST   | /api/sites/:id/restore     | 还原站点                               |
| DELETE | /api/sites/trash/:id       | 永久删除站点                           |
| GET    | /api/sites/exists          | 检查站点是否存在（含 inTrash）         |
| POST   | /api/upload                | 上传图片（保留兼容）                   |

## 移动端（Flutter）

`mobile/` 是 Android app（个人自用；作者主要用平板）：内置浏览器（多标签、视频全屏、长按收藏置顶）+ 收藏库 + 站点页，数据走同一服务器。

- 设计：`docs/superpowers/specs/2026-11-09-readlater-mobile-flutter-design.md`
- 计划：`docs/superpowers/plans/2026-11-09-mobile-app-v1.md`
- 工具链：Flutter 3.38.10、JDK 21、AGP 8.11.1；Flutter 优先使用 Android Studio 自带 JDK，需用 `flutter config --jdk-dir="<JDK21路径>"` 指定（不要把本机路径写进 `gradle.properties`）
- 开发/测试：`cd mobile && flutter run`、`flutter test`
- 集成测试（需设备/模拟器）：`flutter test integration_test/long_press_test.dart -d <device-id>`
- 构建：`flutter build apk --release --target-platform android-arm64 --split-per-abi`（只出 arm64；其他 ABI 需要者自行编译；个人侧载，release 用 debug 签名）
- 包名 `com.cpf23333.readlater`，`minSdk 26`

## 关键代码位置

### 图片提取 (utils/imageExtractor.ts)

- `extractNearbyImage()` - 主提取函数
- `imageToBase64()` - 转换 blob/URL 为 base64
- `defaultImageExtractor()` - 默认提取策略
- `executeCustomExtractor()` - 执行自定义 JS

### 图片 URL 处理 (utils/imageUrl.ts)

- `getThumbUrl()` - 根据原图 URL 生成缩略图 URL
- `handleThumbError()` - 缩略图加载失败回退到原图

### URL 标准化 (server/src/utils/url.ts)

- `normalizeUrl()` - 与前端统一的标准化逻辑，用于链接去重

### 后台脚本 (entrypoints/background.ts)

- `handleMessage()` - 消息处理（CAPTURE_TAB, FETCH_TITLE 等）
- `captureTab()` - 获取页面截图
- `fetchPageTitle()` - 获取页面标题
- 右键菜单点击处理

### 服务器开发 (server/)

**开发模式：**

```bash
cd server
npm run dev    # 使用 tsx watch 热重载
```

**构建：**

```bash
cd server
npm run build  # 编译 TypeScript 到 dist/
npm start      # 运行编译后的代码
```

**Docker 构建：**

```bash
cd server
docker-compose up --build -d
```

**关键函数：**

- `processImage()` - 处理图片数据（base64/URL/路径），并生成缩略图
- `saveBase64ToFile()` - 保存 base64 为文件
- `downloadImage()` - 下载网络图片
- `createThumbnail()` - 使用 sharp 生成缩略图
- `findLinkByNormalizedUrl()` - 基于标准化 URL 的去重查询
- `batchDeleteLinks()` / `batchRestoreFromTrash()` / `batchPermanentlyDelete()` - 批量操作
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
pnpm dev              # 开启 sourcemap，保留 console
pnpm build            # 生产构建
pnpm typecheck        # 前端类型检查
pnpm typecheck:server # 后端类型检查
pnpm test:unit run    # 运行单元测试
pnpm lint             # 代码检查
pnpm format           # 格式化
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

**步骤 1：在有网络的机器上导出镜像**

```bash
cd server
./build.sh --export
```

输出：`read-later-server.tar`

**步骤 2：复制到目标服务器并部署**

```bash
cd server

# 创建 .env（如果还没有）
cat > .env <<EOF
API_KEY=$(openssl rand -base64 32)
PORT=3000
DATA_PATH=./data
EOF

# 加载镜像并启动
./reload.sh
```

Windows:

```cmd
cd server
reload.bat
```

**步骤 3：更新（有新版时）**

```bash
# 1. 在有网络的机器上重新执行 ./build.sh --export
# 2. 复制 read-later-server.tar 到服务器 server/ 目录
# 3. 执行更新
./reload.sh  # Linux/Mac
# 或
reload.bat   # Windows
```

离线部署使用：

- `read-later-server.tar` - Docker 镜像
- `docker-compose.yml` - 部署配置（在线/离线通用，离线时带 `--no-build`）
- `reload.sh/.bat` - 镜像加载/更新脚本

### 环境变量（必需）

| 变量       | 说明                 | 示例                      |
| ---------- | -------------------- | ------------------------- |
| `API_KEY`  | API 鉴权密钥（必须） | `openssl rand -base64 32` |
| `PORT`     | 服务端口             | `3000`                    |
| `DATA_DIR` | 数据目录             | `/app/data`               |

## CI 与工作流

项目使用 **Forgejo Actions** 进行 CI 构建，所有工作流定义在 `.forgejo/workflows/` 目录下。

### 工作流列表

| 工作流                   | 说明                         | 触发方式                    |
| ------------------------ | ---------------------------- | --------------------------- |
| `release.yml`            | 构建扩展并创建 Release       | `workflow_dispatch`（手动） |
| `build-extension.yml`    | 构建 Chrome/Firefox 扩展产物 | `workflow_dispatch`（手动） |
| `build-server-image.yml` | 构建服务器 Docker 镜像       | `workflow_dispatch`（手动） |
| `update-ci-image.yml`    | 构建并推送 `readlater-ci`    | `workflow_dispatch`（手动） |

> 所有工作流均为**手动触发**，不再关联 push/pull_request 事件。

### CI 镜像 (`readlater-ci`)

工作流共用统一的 CI 镜像 `${CI_REGISTRY}/readlater-ci:latest`（通过 Forgejo 项目变量 `CI_REGISTRY` 配置），基于 `node:24`（Debian），预装：

- `pnpm`（全局）
- `buildah` + `skopeo`（容器镜像构建）
- `python3` + `make` + `g++`（原生模块编译）
- `curl` + `jq`

**构建 CI 镜像：**

```bash
cd server/ci
# 1. 复制 .env.example 为 .env 并编辑镜像源
# 2. 构建并推送
./build-and-push.sh <registry> [name] [tag]
# 示例：
./build-and-push.sh your-registry readlater-ci latest
```

**镜像 Dockerfile**: `server/ci/Dockerfile`

- 支持通过 `server/ci/.env` 配置基础镜像、apt 源、npm registry、insecure registries
- 也可通过 build args 直接传入（详见 Dockerfile 顶部注释）
- `Batch 脚本 (.bat)` 构建后需确认 **CRLF 换行符**（`unix2dos` 修复）

### 工作流关键配置

- `actions/checkout@v7`
- `actions/cache@v6`（缓存 `pnpm store` 与 `node-gyp` 缓存）
- `forgejo/upload-artifact@v5`
- npm 源通过 Forgejo 项目变量 `NPM_CONFIG_REGISTRY` 配置
- Docker 基础镜像/CI 镜像通过 Forgejo 项目变量 `CI_REGISTRY` 配置
- CI 镜像基础镜像通过 Forgejo 项目变量 `CI_BASE_IMAGE` 配置（可选，默认 `node:24`）
- CI 镜像 apt 源通过 Forgejo 项目变量 `APT_REPO_DEBIAN` / `APT_REPO_SECURITY` 配置（可选）
- Docker 镜像加速通过 Forgejo 项目变量 `DOCKER_MIRROR` 配置（如 `your-registry`）
- Buildah 私有 HTTP 仓库通过 Forgejo 项目变量 `PRIVATE_REGISTRIES` 配置（逗号分隔）
- `update-ci-image.yml` 调用 `server/ci/build-and-push.sh` 构建并推送 CI 镜像
- `build-server-image.yml` 使用 Buildah + Skopeo 构建并导出离线部署包

## 开发注意事项

### 文件编码规范

- **Shell 脚本** (`.sh`): UTF-8 无 BOM, LF 换行
- **Batch 脚本** (`.bat`): UTF-8 无 BOM, CRLF 换行
- **代码文件**: UTF-8 无 BOM

### Docker 多阶段构建

```dockerfile
# 阶段 1：构建（含编译工具）
FROM node:24-alpine AS builder
RUN apk add --no-cache python3 make g++
RUN npm install

# 阶段 2：运行（仅运行时文件）
FROM node:24-alpine
COPY --from=builder /app/node_modules ./node_modules
```

镜像体积：~200MB → ~80MB

## 版本策略

项目采用 **SemVer** 语义化版本：

- 扩展版本号维护在根目录 `package.json` 的 `version` 字段。
- 服务器版本号维护在 `server/package.json` 的 `version` 字段。
- 发布扩展：给当前 commit 打标签 `v<扩展版本号>`（如 `v1.0.0`），然后手动触发 `release.yml`。
- 发布服务器镜像：给当前 commit 打标签 `server-v<服务器版本号>`（如 `server-v2.0.0`），然后手动触发 `build-server-image.yml`。
- 详细的变更记录见 [CHANGELOG.md](./CHANGELOG.md)。

## 扩展商店发布准备

### 已准备的物料

- **图标**：`public/icon/` 下已包含 16/32/48/96/128 PNG；商店上传通常使用 128px；
- **隐私政策**：`public/privacy.html`，发布前需部署到可访问的 URL 并替换 `homepage_url`；
- **商店文案**：`stores/chrome.md`、`stores/firefox.md`，分别对应 Chrome Web Store 和 Firefox Add-ons；
- **Manifest 元信息**：`wxt.config.ts` 中已配置 `author`、`homepage_url`、`default_locale`。

### 发布前检查清单

1. 版本号：确认根目录 `package.json` 的 `version` 与 `wxt.config.ts` 的 `manifest.version` 一致；
2. 构建产物：执行 `pnpm build` 与 `pnpm zip`，检查 `.output/` 产物；
3. 隐私政策链接：将 `public/privacy.html` 部署到公网，并在 `stores/*.md` 和 manifest 中更新真实地址；
4. 截图：准备 1280×800 或 1400×560 的商店展示截图（Popup、链接管理器、设置页、深色模式）；
5. Chrome Web Store：使用 [Chrome 开发者后台](https://chrome.google.com/webstore/devconsole/) 上传 zip；
6. Firefox Add-ons：使用 [AMO 开发者中心](https://addons.mozilla.org/developers/) 上传，注意 Firefox 对 `<all_urls>` 的审核要求更严格；
7. 更新日志：在 `CHANGELOG.md` 中补充扩展版本变更；
8. 触发 CI：给 commit 打标签 `v<版本号>` 后手动触发 `.forgejo/workflows/release.yml`。

## 相关文件

- [FEATURES.md](./FEATURES.md) - 功能清单
- [CHANGELOG.md](./CHANGELOG.md) - 变更日志
- [server/README-DEPLOY.md](./server/README-DEPLOY.md) - 服务器部署指南
- [server/SECURITY.md](./server/SECURITY.md) - 安全配置说明
