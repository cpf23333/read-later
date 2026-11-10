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

- [ ] 标签页导入工具（v1）：`tools/import-tabs`，PC adb + Chromium DevTools（spec 16.3）
- [ ] 免电脑标签页导入 spike：无线调试 + app 内 ADB host，或 Shizuku 直连 `chrome_devtools_remote`（spec 16.7，需真机验证）
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

## 10. CI 构建与镜像优化（Forgejo）

> 结论：`readlater-ci`（扩展/服务端）与移动端镜像保持独立，不合并；移动端镜像体积 6.85GB，合并会拖慢所有 CI job。

### 已完成

- [x] 移动端镜像采用 `ghcr.io/cirruslabs/flutter:3.38.10`（Flutter 3.38.10 + JDK 21 + Android SDK 36）
- [x] 派生镜像 `mobile/ci/Dockerfile` 补 Node（Gitea/Forgejo 的 JS action 需要 `node`）
- [x] 派生镜像已构建并验证（15.5GB，含 Node/NDK/CMake/pub/Gradle 缓存）
- [x] 新增 `build-mobile-apk.yml`（手动触发，arm64 APK artifact）
- [x] workflow 支持 `MOBILE_CI_IMAGE`、`PUB_HOSTED_URL` 变量

### 待优化

- [ ] **移动端镜像预装完整构建链**：在 `ci/mobile-ci/Dockerfile` 中预装 NDK 29.0.13599879 / 28.2.13676358、CMake 3.22.1、build-tools 35/36、platform 34/35/36、Gradle 8.14 发行包与 Gradle 依赖缓存、`~/.pub-cache`；CI 可改为离线构建，避免每次下载 SDK/NDK/CMake
- [ ] **移动端 pub cache 预置**：构建 `readlater-android-ci` 镜像时复制 `mobile/pubspec.lock` 并执行 `flutter pub get`，把 `/root/.pub-cache` 打进镜像；CI 改为 `flutter pub get --offline`（首选，避免每次 CI 访问 pub.dev）
- [ ] **Gradle 缓存**：移动端 workflow 加 `actions/cache@v6` 缓存 `~/.gradle/caches`、`~/.gradle/wrapper`，按 `mobile/android/**/*.gradle*` + `gradle-wrapper.properties` 做 key
- [ ] **Nexus Maven proxy**：为 Android Gradle 的 `google()` / `mavenCentral()` 依赖建 Maven proxy（8081 `/repository/maven-*`），通过 `settings.gradle.kts` 或 init script 指向 Nexus，减少公网 Maven 下载
- [ ] **PUB_HOSTED_URL 策略**：保持可选；公共镜像（如 `https://pub.flutter-io.cn`）只作为兜底。Nexus raw proxy 只能缓存 pub 元数据，`archive_url` 是 pub.dev 绝对地址会绕过 Nexus，不作为完整 pub 源
- [ ] **runner 镜像缓存**：确认 `docker_dind` 的存储不被频繁清理，避免每次 job 重新拉 6.85GB；如空间不足再评估 `docker system prune` 策略
- [ ] **移动端镜像构建脚本/文档**：Docker Hub 不可达时用 `--build-arg NODE_IMAGE=<内网 Debian node 镜像>`；构建、验证、推送步骤写进 README/AGENTS
- [ ] **固定升级流程**：Flutter/JDK/Android SDK 升级时重建 `readlater-android-ci`，更新 `MOBILE_CI_IMAGE` tag；不要 unpinned `latest`
- [ ] **验证后清理测试分支**：生产镜像验证通过后删除 `ci/mobile-ci-verify` 分支和 `.forgejo/workflows/build-mobile-apk-verify.yml`；生产 `MOBILE_CI_IMAGE` 指向 `<nexus-host>:8083/readlater-android-ci:3.38.10`
- [ ] **CI 构建文件抽离到顶层 `ci/`**：CI 是仓库级而非 server 子包能力。建议 `ci/readlater-ci/`（Dockerfile、build-and-push.*、.env.example）、`ci/mobile-ci/`（Dockerfile），更新 workflow 与 AGENTS/README 路径；`server/Dockerfile`、`deploy.Dockerfile`、build/reload、`push-server-to-dockerhub.*` 属于部署，保留在 `server/`。在 APK 构建验证通过后单独分支执行，避免和移动端验证混在一起
- [ ] **待推送**：新镜像 `<nexus-host>:8083/readlater-android-ci:3.38.10` 构建完成后推送到 Nexus`n- [ ] **Nexus 清理（可选）**：评估是否删除早先的 `<nexus-host>:8083/readlater-flutter:3.38.10` 别名，节省 6.85GB；若保留则明确它只是 Flutter 官方镜像的 Nexus 副本
