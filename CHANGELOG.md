# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/lang/zh-CN/).

## [Unreleased]

### Mobile

#### Added

- 新增 `mobile/` Flutter Android app：内置浏览器（多标签、地址栏、前进后退、网页视频全屏）。
- 长按链接弹出自绘菜单："收藏到稍后再看"置顶、"收藏主站"第二；自动提取标题、附近图片、可见区域截图并保存到服务器。
- 收藏库：网格/列表、搜索、排序、分页、删除进回收站。
- 站点页：一个站点一张卡片（图标/名称），支持收藏主站、删除进回收站。
- 回收站：链接与站点两个 tab，支持还原与永久删除。
- 设置：服务器地址/API Key/连接测试、主题切换、清除浏览数据、标签页导入说明。
- 服务端新增 `/api/sites` 站点收藏 API（含回收站，软删除）。

### Server

#### Added

- 站点收藏：新增 `sites` 表与 `/api/sites` 路由组（列表、新增、软删除、回收站、还原、永久删除、存在性检查）。
- 站点重复收藏：活跃站点幂等返回；回收站中的站点自动恢复并更新标题/图标。

## [0.9.0] - 2026-08-11

### Extension

#### Added

- 搜索优化：多关键字 AND 匹配、域名过滤交给后端、搜索框 300ms 防抖。
- 链接去重：保存与导入时基于标准化 URL 检测重复，导入预览支持批量查重接口。
- 批量操作：链接列表支持批量删除；回收站支持批量还原与批量永久删除。
- 图片缩略图：链接列表优先加载服务器生成的缩略图，加载失败自动回退到原图。
- 测试：引入 Vitest 与示例组件测试。
- 代码质量：升级 ESLint 10 并配置 Vue 官方 TS 规则；新增 Prettier 配置（保留分号与尾随逗号）。
- 类型检查：前后端分别新增 `pnpm typecheck` 与 `pnpm typecheck:server` 命令。

#### Changed

- 升级 WXT 到 0.21.3。
- 升级 Vue、vue-tsc、@eslint/js、@types/jsdom、jsdom 等依赖到最新兼容版本。

### Server

#### Added

- 图片缩略图：保存原图后使用 sharp 自动生成 320×240 JPEG 缩略图到 `/images/thumbs/`。
- 批量操作接口：`POST /api/links/batch-delete`、`POST /api/trash/batch-restore`、`POST /api/trash/batch-delete`。
- 去重接口：`GET /api/links/exists`、`POST /api/links/check-batch`，基于 `normalized_url` 字段查询。
- 数据库新增 `links.normalized_url` 列与索引，启动时自动迁移并回填已有数据。
- 搜索接口支持多 token AND 匹配。

#### Changed

- 升级 hono、@hono/node-server、better-sqlite3、tsx、@types/* 等依赖到最新兼容版本。
- 最低 Node 版本要求提升到 `>=20.0.0`。
- `archiver` 升级到 v8，改用 `ZipArchive` 类构造。
- `server/Dockerfile` 增加 `vips-dev` / `vips` 依赖以支持 sharp。

#### Fixed

- 删除/还原链接时同步移动缩略图文件。
- 单条删除链接时图片文件也正确移入 `images/deleted/`。
