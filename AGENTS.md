# ReadLater - 稍后再看 项目指南

## 项目概述

一个浏览器扩展，用于收藏和管理链接，支持自动截图、图片提取和服务器同步。

## 技术栈

- **框架**: WXT (浏览器扩展开发框架)
- **前端**: Vue 3 + TypeScript
- **样式**: 原生 CSS (Scoped)
- **存储**: 服务器 SQLite 数据库（通过 HTTP API）
- **服务器**: Express + SQLite (server/)
- **构建**: Vite

## 项目结构

```
.
├── entrypoints/           # 扩展入口点
│   ├── background.ts      # 后台脚本（右键菜单、消息处理）
│   ├── content.ts         # 内容脚本（页面交互）
│   ├── popup/             # 弹出窗口
│   ├── options/           # 设置页面
│   └── link-manager/      # 链接管理页面
├── utils/                 # 工具模块
│   ├── storage.ts         # 类型定义
│   ├── apiStorage.ts      # 服务器 API 存储
│   ├── hybridStorage.ts   # 统一存储接口
│   └── imageExtractor.ts  # 图片提取逻辑
├── server/                # 后端服务器
│   ├── server.js          # Express + SQLite 服务
│   ├── Dockerfile         # Docker 构建配置
│   └── docker-compose.yml # Docker Compose 配置
├── components/            # 共享组件
└── assets/                # 静态资源
```

## 核心功能模块

### 1. 链接收藏
- 右键菜单保存链接（background.ts）
- 自动提取页面截图、附近图片
- 自定义 JS 提取规则

### 2. 存储层 (utils/)
- **storage.ts**: 仅包含类型定义（LinkItem, CustomJsConfig, DeleteRecord 等）
- **apiStorage.ts**: 服务器 API 调用（链接增删改查、图片上传、导入导出）
- **hybridStorage.ts**: 统一存储接口，直接调用服务器 API

### 3. 链接管理 (link-manager/App.vue)
- 网格/列表视图
- 搜索、域名筛选、排序
- 批量操作
- 回收站管理

### 4. 设置页面 (options/App.vue)
- 图片提取器配置
- 服务器配置
- 导入/导出 JSON

## 数据流

```
用户操作 → hybridStorage.ts (统一存储接口)
                ↓
         apiStorage.ts
                ↓
         server.js (SQLite)
```

## 存储策略

### 核心原则
1. **纯服务器存储** - 所有数据直接同步到服务器 SQLite 数据库
2. **服务器必须配置** - 使用前必须配置并连接服务器
3. **图片自动上传** - Base64 图片自动上传到服务器并转换为文件路径

### 使用方式
```typescript
// 直接导入统一存储接口
import { getLinks, addLink, deleteLink } from '@/utils/hybridStorage';

// 所有操作直接同步到服务器
const result = await getLinks(1, 50);
await addLink({ url, title, ... });
```

### API 功能列表
- `apiGetLinks()` - 分页获取链接列表
- `apiSearchLinks()` - 搜索链接
- `apiAddLink()` - 添加新链接
- `apiDeleteLink()` - 删除链接（移入回收站）
- `apiGetTrash()` - 获取回收站列表
- `apiRestoreFromTrash()` - 从回收站还原
- `apiPermanentlyDelete()` - 永久删除
- `apiUploadImage()` - 上传图片
- `apiGetStats()` - 获取统计数据
- `apiGetDomainStats()` - 获取域名统计
- `apiExport()` / `apiImport()` - 导入导出

## 服务器 API 端点

- `GET /api/links` - 获取链接列表（支持分页、搜索、域名过滤）
- `POST /api/links` - 添加链接
- `DELETE /api/links/:id` - 删除链接
- `POST /api/links/batch` - 批量添加
- `GET /api/search?q=xxx` - 搜索链接
- `GET /api/domains` - 获取域名统计
- `GET /api/trash` - 获取回收站
- `POST /api/trash/:id/restore` - 还原链接
- `DELETE /api/trash/:id` - 永久删除
- `GET /api/stats` - 获取统计
- `GET /api/export` - 导出数据
- `POST /api/import` - 导入数据
- `POST /api/upload` - 上传图片
- `GET /api/health` - 健康检查

## 服务器部署

```bash
cd server
# 在线构建
docker-compose up -d

# 离线部署（无外网环境）
# 1. 在联网机器运行 prepare-offline.sh
# 2. 复制 readlater-offline.tar.gz 到目标机器
# 3. 解压运行 start-offline.sh
```

## 开发命令

```bash
pnpm install    # 安装依赖
pnpm dev        # 开发模式
pnpm build      # 构建生产版本
pnpm compile    # TypeScript 类型检查
```

## 注意事项

1. **IndexedDB 已移除**: 之前使用 IndexedDB 作为本地缓存，现在直接使用服务器存储
2. **服务器必须配置**: 如果没有配置服务器，扩展将无法保存数据
3. **回收站**: 删除操作是软删除，可在回收站还原
4. **图片存储**: 图片作为独立文件存储在服务器的 `data/images` 目录

## 相关文件

- [FEATURES.md](./FEATURES.md) - 功能清单
- [server/README-DEPLOY.md](./server/README-DEPLOY.md) - 服务器部署指南
