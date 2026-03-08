# ReadLater - 稍后再看 项目指南

## 项目概述

一个浏览器扩展，用于收藏和管理链接，支持自动截图、图片提取和服务器同步。

## 技术栈

- **框架**: WXT (浏览器扩展开发框架)
- **前端**: Vue 3 + TypeScript
- **样式**: 原生 CSS (Scoped)
- **本地存储**: IndexedDB (utils/storage.ts)
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
│   ├── storage.ts         # IndexedDB 本地存储
│   ├── apiStorage.ts      # 服务器 API 存储
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

### 2. 本地存储 (utils/storage.ts)
- IndexedDB 数据库
- LinkItem 结构: id, url, title, nearbyImage, screenshot, sourcePage, createdAt
- 回收站机制（软删除）

### 3. 服务器同步 (utils/apiStorage.ts)
- 替代已移除的 WebDAV
- Express + SQLite 后端
- 支持分页查询、回收站、图片上传

### 4. 链接管理 (link-manager/App.vue)
- 网格/列表视图
- 搜索、域名筛选、排序
- 批量操作
- 回收站管理

### 5. 设置页面 (options/App.vue)
- 图片提取器配置
- 服务器配置
- 导入/导出 JSON

## 数据流

```
用户操作 → hybridStorage.ts (统一存储接口)
                ↓
    ┌──────────┴──────────┐
    ↓                     ↓
服务器可用?          服务器不可用?
    ↓                     ↓
apiStorage.ts      storage.ts (IndexedDB)
    ↓                     ↓
server.js (SQLite)   [待同步队列]
                           ↓
                    服务器恢复时自动同步
```

## 混合存储策略

### 核心原则
1. **优先服务器** - 服务器可用时，优先从服务器读写数据
2. **离线降级** - 服务器不可用时，自动降级到本地 IndexedDB
3. **自动同步** - 后台每分钟检查待同步项目，自动同步到服务器
4. **始终本地** - 所有数据始终先写入本地，再异步同步到服务器

### 使用方式
```typescript
// 直接导入混合存储接口
import { getLinks, addLink, deleteLink } from '@/utils/hybridStorage';

// 所有操作自动处理服务器/本地切换
const result = await getLinks(1, 50);
await addLink({ url, title, ... });
```

### 待同步队列
- 存储在 `browser.storage.local` 中
- 包含操作类型: 'add', 'delete', 'restore', 'permanent_delete'
- 后台脚本每分钟自动尝试同步
- 支持批量同步以提高效率

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

1. **WebDAV 已移除**: 之前使用 WebDAV 同步，现改用 SQLite 服务器
2. **服务器优先**: 如果配置了服务器，扩展优先使用服务器数据
3. **回收站**: 删除操作是软删除，可在回收站还原
4. **图片存储**: 服务器模式下图片作为独立文件存储

## 待办事项

- [ ] 服务器同步的增量同步优化
- [ ] 图片压缩功能
- [ ] 标签系统
- [ ] 全文搜索

## 相关文件

- [FEATURES.md](./FEATURES.md) - 功能清单
- [server/README-DEPLOY.md](./server/README-DEPLOY.md) - 服务器部署指南
