# 稍后再看

一个强大的链接收藏管理浏览器扩展，支持右键/长按保存链接、自动截图、SQLite 服务器同步、回收站和批量管理。

## 功能特性

- 🔗 **一键收藏** - 右键或长按链接快速保存
- 📸 **自动截图** - 保存页面标题、截图和附近图片
- 🖥️ **服务器同步** - 通过自建 SQLite 后端在多台设备间同步数据
- 🗑️ **回收站** - 软删除机制，支持还原和永久删除
- 🔍 **智能搜索** - 多关键字搜索、按域名筛选、按时间范围筛选、排序
- ⚙️ **自定义规则** - 编写 JS 代码自定义图片提取逻辑
- 📦 **导入导出** - 支持 JSON 导入/导出与备份包下载
- 🖼️ **缩略图** - 服务器自动生成图片缩略图，列表加载更省带宽
- ✔️ **链接去重** - 基于标准化 URL 自动检测重复链接
- ⚡ **批量操作** - 批量删除、批量还原、批量永久删除

## 支持的浏览器

- Chrome / Edge / 其他 Chromium 内核浏览器
- Firefox（需构建）
- 支持扩展的 Android 浏览器（Kiwi、Yandex 等）

## 技术栈

- [WXT](https://wxt.dev/) - 浏览器扩展开发框架
- Vue 3 - 前端框架
- TypeScript - 类型安全
- [Hono](https://hono.dev/) - 后端 API 框架
- better-sqlite3 - 服务器 SQLite 数据库
- sharp - 图片缩略图处理

## 开发

```bash
# 安装依赖
pnpm install

# 开发模式
pnpm dev

# 类型检查
pnpm typecheck
pnpm typecheck:server

# 代码检查与格式化
pnpm lint
pnpm format

# 单元测试
pnpm test:unit run

# 构建
pnpm build
pnpm zip
```

## 版本策略

项目采用 **SemVer** 语义化版本：

- 扩展版本号维护在根目录 `package.json` 的 `version` 字段。
- 服务器版本号维护在 `server/package.json` 的 `version` 字段。
- 发布扩展时，给当前 commit 打标签 `v<扩展版本号>`（例如 `v1.0.0`），然后手动触发 `release.yml`。
- 发布服务器镜像时，给当前 commit 打标签 `server-v<服务器版本号>`（例如 `server-v2.0.0`），然后手动触发 `build-server-image.yml`。
- 详细的变更记录见 [CHANGELOG.md](./CHANGELOG.md)。

## 许可证

MIT
