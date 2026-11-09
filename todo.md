# ReadLater 后续计划

## 1. 代码质量与可维护性

- [x] 添加测试框架（Vitest）
- [x] 检查并开启 TypeScript strict 模式
- [x] 配置 ESLint + Prettier
- [x] 检查并更新过期依赖

## 2. 功能完善

- [ ] 导入导出增强（JSON/HTML/Netscape bookmarks）—— 暂不实现
- [x] 搜索优化（多关键字 AND 匹配、域名过滤后端化、搜索防抖）
- [x] 链接去重（服务端标准化 URL 检查）
- [x] 批量操作（后端事务批量删除/还原/永久删除）
- [x] 图片处理优化（sharp 缩略图、删除/还原时同步图片）

## 3. 安全与运维

- [x] 健康检查增强
- [x] Rate limit 调优
- [x] 数据库自动备份
- [x] API Key 管理（多 key、轮换）
- [x] 结构化日志与错误监控

## 4. 文档与发布

- [x] 更新 AGENTS.md / README（CI/CD 流程已变更）
- [x] 制定版本策略与 CHANGELOG
- [x] 扩展商店发布准备

## 5. 体验优化

- [x] UI 美化（Popup/选项页）
- [x] 深色模式
- [x] 键盘快捷键
- [x] 导入进度显示

## 6. 长期规划

- [ ] 用 Go 重构后端服务（降低部署门槛、单二进制分发）—— 暂不实现

## 7. 移动端（Flutter）v1 之外

> 设计见 `docs/superpowers/specs/2026-11-09-readlater-mobile-flutter-design.md`；v1 只做浏览器 + 收藏/站点 + 设置。

- [ ] 标签页导入工具：`tools/import-tabs`，adb + Chromium DevTools（设计见 spec 第 16 节）
- [ ] 导入/导出（JSON/HTML）
- [ ] 下载管理器（Android DownloadManager）
- [ ] 系统分享入口（其他 app 分享链接到本 app）
- [ ] iOS 适配（WKWebView；需要 Mac + 开发者账号）
- [ ] 站点排序/分组/编辑、站点与链接关联
- [ ] 扩展端支持"收藏主站"（复用 `/api/sites`）
- [ ] 标签会话恢复细节、桌面/移动 UA 切换
- [ ] 视频嗅探 + 自研播放器（Media3）、后台播放、画中画
- [ ] 广告拦截/脚本拦截
- [ ] 多用户/多账号（需要后端鉴权体系调整）

## 8. 数据库与性能

- [x] 决策（2026-11-09）：v1 保持 SQLite，不换 PostgreSQL
  - 理由：单用户、数据量小、图片在文件系统；换 PG 的收益不足以抵消部署与代码改动（`database.ts` 需整体异步化）
  - 换库触发条件（满足任一再评估）：多用户共享、需要异地只读副本/高并发写、链接量 10 万+ 且搜索/聚合明显变慢、需要 tsvector/JSONB 级查询
- 换库前先做的低成本优化：
  - [ ] SQLite 开启 WAL、设置 `busy_timeout`
  - [ ] FTS5 全文搜索（标题 + URL）
  - [ ] 复合索引（`created_at`、`normalized_url`）
  - [ ] 图片处理异步化/限流（sharp 是主要 CPU 消耗）
- 迁移成本备忘：schema 简单（links/trash/sites/export_tasks），图片在文件系统；迁移主要改数据库层与备份脚本，属可控范围

## 9. 其他

- [ ] 服务端测试框架（当前无，仅 curl 手测）
- [ ] `AGENTS.md` 补充 mobile 章节与 `/api/sites` API 表
- [ ] 扩展端与移动端行为对齐检查清单
