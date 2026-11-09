# ReadLater 移动端（Flutter）设计

- 日期：2026-11-09
- 状态：已评审通过（v1）；追加：站点收藏（含回收站）、标签页导入；数据库保持 SQLite
- 决策人：项目作者（个人自用）
- 平台：Android 平板优先，代码结构保留 iOS 可移植性

## 1. 背景与目标

现有 ReadLater 是一个 WXT 浏览器扩展（Vue 3 + TypeScript），核心能力是"长按/右键链接 → 收藏 → 自动截图、提取附近图片 → 同步到自建 SQLite 服务器"。

目标是把核心体验搬到一个自带浏览器的 Android 平板 app：用户在 app 内置浏览器里浏览网页，长按链接时弹出**完全自己绘制的菜单**，把"收藏到稍后再看"固定为第一项（浏览器扩展里无法控制 Chrome 菜单顺序，这是本次改动最直接的动机）。

数据仍然只存在自建服务器上，扩展端与移动端共用同一套 API 和数据库。

## 2. 范围

### 2.1 v1 目标（MVP）

1. 内置浏览器：地址栏、前进/后退/刷新、多标签、标签切换、关闭标签、平板横向标签条。
2. 网页视频全屏：站点 `<video>` 全屏可横屏播放、返回后恢复。
3. 长按链接：自绘菜单，"收藏到稍后再看"置顶、"收藏主站"第二；其余项：打开、新标签打开、复制链接、分享、用系统浏览器打开。
4. 收藏链路：标题（目标页 title/og:title，回退链接文字）、可见区域截图、链接附近图片（含 blob URL）、重复检测、保存到服务器。
5. 收藏当前页：工具栏按钮直接收藏当前页面（对应扩展 popup 的"收好当前页面"）。
6. 链接库：网格/列表、搜索、排序、分页、打开链接、删除（进回收站）、回收站还原/永久删除。
7. 设置：服务器地址、API Key、连接测试、主题跟随系统。
8. 长按菜单在 Android 与未来 iOS 上行为一致（不依赖系统 context menu）。
9. 站点收藏：独立"站点"页，一个站点一张卡片（图标 + 名称）；可从浏览器"收藏主站"、打开、删除（进回收站）。服务端新增 `/api/sites`（见 5.4）。

### 2.2 非目标（v1 不做）

- iOS 构建与适配（结构上预留，不实现）。
- 视频嗅探、自研播放器（Media3/ExoPlayer）、后台播放、画中画。
- 广告拦截、脚本拦截、下载管理器（下载仅做基础兜底，见 6.6）。
- 导入/导出、自定义 JS 提取器编辑、统计图表、标签系统。
- 离线缓存、增量同步、本地数据库（服务器仍是唯一数据源）。
- 系统分享入口（其他 app 分享链接到本 app），列为 v1.1。
- 站点排序/分组/编辑、站点关联链接（v1 站点删除进回收站，见 5.4）。
- app 内直接读取平板 Chrome/Brave 的标签页（平台不提供该能力，见 16）。
- 标签页导入脚本（设计见 16，排期见 `todo.md`；v1 不做）。

## 3. 关键决策

| 决策 | 结论 | 理由 |
| --- | --- | --- |
| 框架 | Flutter 3.x（Dart 3） | 个人自用、Android 优先但保留 iPad 可能；UI 与逻辑一套代码；`flutter_inappwebview` 覆盖多标签、注入、截图、全屏视频 |
| 浏览器内核 | 系统 WebView（`flutter_inappwebview` 6.x） | 不引入 GeckoView/Cronet，平板场景够用；iOS 侧未来自动落到 WKWebView |
| 长按菜单触发 | 注入 JS 检测长按 + Flutter 自绘 bottom sheet | 菜单顺序 100% 可控；避开 iOS 系统 callout 顺序不可控的问题；与扩展 `content.ts` 逻辑同源 |
| 管理页实现 | Flutter 原生重写 | 若嵌 Vue 页面会引入双 UI 体系与 bridge，破坏 iOS 移植性；列表页功能虽多但不复杂 |
| 状态管理 | Riverpod（`flutter_riverpod`） | 依赖注入显式，API client / 配置 / tab 状态可测试；避免全局单例 |
| 导航 | `go_router` | 声明式路由，便于以后接 deep link |
| 数据源 | 现有 Hono 服务器；仅新增 `/api/sites`（见 5.4），现有接口与数据表不动 | 契约稳定，扩展与 app 共用；去重、图片处理都在服务端 |
| 站点数据模型 | 服务端新建独立 `sites` 表（4 个端点） | 站点字段（origin/图标）与链接差异大，独立表避免污染 links/trash；列表可按站点批量返回 |
| 标签页导入 | 外部 adb 工具（Node 脚本），不做进 app | 平板不向第三方 app 暴露标签页；adb+CDP 是唯一可行路径，app 内无法完成 |
| 数据库 | 保持 SQLite（v1 不换 PostgreSQL） | 单用户、数据量小、图片在文件系统；换 PG 的收益不足以抵消部署与代码改动，触发条件与优化项记入 todo.md |
| 配置存储 | `flutter_secure_storage`（API Key、服务器地址、自定义配置） | Keystore 加密；个人自用不做多账号 |
| 主题 | Material 3，跟随系统，支持深色 | 与扩展视觉习惯一致即可，不做像素级复刻 |

## 4. 总体架构

```
┌────────────────────────────────────────────────────────┐
│ Flutter (Dart)                                          │
│                                                        │
│  UI 层        BrowserScreen / LibraryScreen / SitesScreen     │
│               Settings / TabStrip / BrowserToolbar            │
│               LongPressSheet                                  │
│  ────────────────────────────────────────────────────  │
│  应用层       BrowserNotifier(TabManager)               │
│               CaptureService / LibraryNotifier          │
│  ────────────────────────────────────────────────────  │
│  数据层       ApiClient(Dio) / ConfigStore / SessionStore│
│  ────────────────────────────────────────────────────  │
│  平台适配     WebViewSettings / SystemChrome / Intent   │
└───────────────┬────────────────────────────────────────┘
                │ flutter_inappwebview（平台视图）
┌───────────────▼────────────────────────────────────────┐
│ Android System WebView / iOS WKWebView                  │
│   页面上下文：assets/js/inject.js（长按检测 + 提取）      │
└───────────────┬────────────────────────────────────────┘
                │ HTTPS + Bearer Token
┌───────────────▼────────────────────────────────────────┐
│ 现有 Hono + SQLite 服务器（server/；新增 /api/sites）      │
└────────────────────────────────────────────────────────┘
```

### 4.1 目录结构

```
mobile/
├── pubspec.yaml
├── analysis_options.yaml
├── assets/
│   ├── js/inject.js              # 注入脚本（长按检测 + 提取），纯 JS 无构建
│   ├── test/                     # 本地 fixture 页面（集成测试用）
│   └── images/                   # 占位图等
├── lib/
│   ├── main.dart
│   ├── app.dart                  # MaterialApp.router、主题
│   ├── router.dart
│   ├── core/
│   │   ├── api/api_client.dart
│   │   ├── api/models.dart
│   │   ├── api/errors.dart
│   │   ├── config/config_store.dart
│   │   └── util/url_utils.dart
│   ├── features/
│   │   ├── browser/
│   │   │   ├── browser_screen.dart
│   │   │   ├── browser_notifier.dart
│   │   │   ├── tab_webview.dart
│   │   │   ├── tab_strip.dart
│   │   │   ├── browser_toolbar.dart
│   │   │   ├── long_press_sheet.dart
│   │   │   └── capture_service.dart
│   │   ├── library/
│   │   │   ├── library_screen.dart
│   │   │   ├── library_notifier.dart
│   │   │   ├── link_card.dart
│   │   │   └── trash_screen.dart
│   │   ├── sites/
│   │   │   ├── sites_screen.dart
│   │   │   └── site_card.dart
│   │   └── settings/settings_screen.dart
│   ├── platform/
│   │   ├── webview_settings.dart  # Android/iOS 设置差异集中在这里
│   │   └── system_ui.dart         # 全屏、方向、沉浸式
│   └── shared/widgets/
├── test/
└── integration_test/
```

### 4.2 可移植边界

以下代码必须保持平台无关，iOS 移植时直接复用：

- `core/`（API client、模型、配置、URL 工具）
- `assets/js/inject.js`（页面上下文，与平台无关）
- `features/*_notifier.dart`（业务编排）
- 所有不直接调用平台通道的 widget

平台相关代码只允许出现在 `platform/` 和少数 `WebView` 配置开关里，用 `defaultTargetPlatform` 分支而非散落各处的 `Platform.isAndroid`。

## 5. 数据与接口

### 5.1 现有 API（不改动，扩展与 app 共用）

| 用途 | 方法/路径 |
| --- | --- |
| 健康检查 | `GET /api/health` |
| 列表 | `GET /api/links?page&pageSize&sortBy&sortOrder&search&domain` |
| 新增 | `POST /api/links` |
| 去重检查 | `GET /api/links/exists?url=` → `{ exists, link? }` |
| 删除（进回收站） | `DELETE /api/links/:id` |
| 回收站 | `GET /api/trash`（返回全部，无分页参数，客户端本地分页） |
| 还原 | `POST /api/trash/:id/restore` |
| 永久删除 | `DELETE /api/trash/:id` |
| 统计 | `GET /api/stats` |
| 站点 | `GET/POST/DELETE /api/sites*`（新增，见 5.4） |

- `page` 从 1 开始；`pageSize` 默认 50；`sortBy` 取 `created_at` | `title`；`sortOrder` 取 `asc` | `desc`。
- 响应统一为 `{ success, data?, total?, error? }`。
- 请求头：`Authorization: Bearer <API_KEY>`。
- `POST /api/links` 的 payload 与扩展 `apiStorage.ts` 完全一致，字段为 **snake_case**（服务端单条新增只认这套字段名）：

```json
{
  "url": "https://example.com/a",
  "title": "页面标题",
  "nearby_image": "data:image/jpeg;base64,... 或 https://...",
  "screenshot": "data:image/jpeg;base64,...",
  "source_page": "https://example.com/list",
  "custom_data": { "linkText": "链接文字", "platform": "android" }
}
```

- `id` 可不传，服务端生成；`created_at` 可不传，服务端取当前时间。
- 服务端负责 base64 落盘、缩略图、URL 标准化去重，客户端不重复实现。

### 5.2 ApiClient 约定

```dart
abstract class ApiClient {
  Future<HealthStatus> health();
  Future<ExistsResult> exists(String url);          // {exists, link?}
  Future<void> addLink(AddLinkRequest req);         // 服务端不回传新 id
  Future<PagedLinks> listLinks({int page, int pageSize, String? search,
      String? domain, String sortBy, String sortOrder});
  Future<void> deleteLink(String id);
  Future<List<TrashItem>> listTrash();              // 全量返回
  Future<String> restoreTrash(String id);           // 返回新 id
  Future<void> purgeTrash(String id);
  Future<Stats> stats();
  Future<List<Site>> listSites();
  Future<Site> addSite(SiteInput input);        // 已存在则幂等返回；在回收站则恢复
  Future<void> deleteSite(String id);           // 软删除，进回收站
  Future<List<Site>> listSiteTrash();
  Future<void> restoreSite(String id);
  Future<void> purgeSite(String id);
  Future<SiteExistsResult> siteExists(String origin);  // {exists, inTrash}
}
```

- 超时：普通请求 10s，`addLink` 30s（图片 base64 较大）。
- 错误分类：`NotConfigured`、`NetworkError`、`AuthError(401)`、`Validation(400)`、`ServerError(5xx)`，统一映射为可展示文案。
- 不自动重试 `addLink`；服务端 `POST /api/links` **不做去重**，客户端保存前必须调用 `GET /api/links/exists` 判断（与扩展 popup 行为一致）。
- 401 统一行为：提示"API Key 无效"，并提供跳转设置页入口。

### 5.3 配置模型

```dart
class ServerConfig {
  final String baseUrl;   // 必填，http(s)
  final String apiKey;    // 必填
  final bool enabled;     // 默认 true
}
```

- 保存前先 normalize（去掉末尾 `/`）。
- 未配置时：浏览器可用，收藏与列表提示"先去设置服务器"。

### 5.4 站点收藏 API（后端新增）

站点 = 一个 URL 的 origin（`scheme://host[:port]`），与链接是两类数据，独立建表；删除进回收站（软删除）。

```sql
CREATE TABLE IF NOT EXISTS sites (
  id          TEXT PRIMARY KEY,
  url         TEXT NOT NULL,            -- 归一化后的 origin，如 https://example.com
  title       TEXT,
  icon_url    TEXT,                     -- 采集到的 favicon 地址，可为空
  created_at  INTEGER NOT NULL,
  deleted_at  INTEGER                   -- NULL=正常，非 NULL=在回收站
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_sites_url ON sites(url);
CREATE INDEX IF NOT EXISTS idx_sites_deleted ON sites(deleted_at);
```

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/api/sites` | 正常站点（`deleted_at IS NULL`），按 `created_at` 倒序 |
| POST | `/api/sites` | 新增 `{url, title, icon_url?}`；url 归一化为 origin。正常站点已存在→幂等返回已有记录；已在回收站→恢复并更新 title/icon_url |
| DELETE | `/api/sites/:id` | 软删除（写入 `deleted_at`，进回收站） |
| GET | `/api/sites/trash` | 回收站站点，按 `deleted_at` 倒序 |
| POST | `/api/sites/:id/restore` | 还原（清空 `deleted_at`） |
| DELETE | `/api/sites/trash/:id` | 永久删除（仅回收站内可用） |
| GET | `/api/sites/exists?url=` | `{exists, inTrash}`，按 origin 比较 |

- **路由顺序**：`/trash` 与 `/trash/:id` 必须注册在 `/:id` 之前，避免 `trash` 被当成 id。
- 鉴权、限流、错误格式与现有 `/api/*` 一致。
- 不改动 `links` / `trash` 表与现有接口；不引入站点与链接的关联。
- 站点只有 `icon_url` 文本，不落盘图片，因此删除/还原/永久删除都不涉及文件操作。
- 服务端改动清单：`utils/database.ts`（建表与 CRUD）、`routes/sites.ts`、`index.ts` 挂载、`types/index.ts` 增加 `Site` 类型；`AGENTS.md` API 表补一行。
- 验证方式（服务端暂无测试框架）：`curl` 覆盖四个以上场景——正常增删查、401、重复收藏（活跃/回收站两种）、还原、永久删除、非法 url。

### 5.5 站点与链接的展示关系

- 收藏库（links）与站点页（sites）完全独立，互不出现。
- 收藏主站时不写入 links；收藏链接时不写入 sites。
- 两者共用同一服务器、同一 API Key。

## 6. 浏览器模块

### 6.1 标签模型

```dart
class BrowserTab {
  final String id;          // uuid
  final String url;
  String title;
  String? favicon;
  bool loading;
  bool canGoBack;
  bool canGoForward;
}
```

- 每个标签对应一个 `InAppWebView` widget，放在 `IndexedStack` 中，非活动标签用 `Offstage` 隐藏（保持页面存活，不销毁）。
- 标签懒创建：点击"新标签"或首次激活时才创建 WebView；恢复会话时只有活动标签立即加载，其余在首次激活时加载其 URL。
- `TabRegistry` 保存 `tabId → InAppWebViewController`，供工具栏操作；不把 controller 放进不可变状态。
- 上限 10 个标签；超限时关闭最久未使用的非活动标签。关闭标签时移除 widget（插件随之释放 WebView）。
- 会话持久化：`{urls, activeIndex}` 防抖写入 `SharedPreferences`，启动时恢复 URL 列表，不恢复滚动位置与表单。

### 6.2 导航与生命周期

- 地址栏：显示当前 URL，可编辑；输入不含 scheme 时自动补 `https://`，含空格则走搜索（先接入 `https://www.bing.com/search?q=`，搜索源可配置）。
- `onUpdateVisitedHistory` 同步 URL；`onTitleChanged` 同步标题；`onFaviconChanged` 同步图标。
- 返回键优先级：`WebView.canGoBack()` → back；否则多标签时关闭当前标签；否则退出。
- `PopScope` 实现拦截，避免 Android 直接杀 Activity。
- 后台标签：切走后暂停其定时器与媒体播放，切回恢复（使用插件提供的 pause/resume 能力或 WebView 生命周期接口，具体 API 在 M0 确认）。
- 外链处理：`intent://`、`mailto:`、`tel:`、非 http(s) scheme 交给 `url_launcher`；同一 scheme 的 http(s) 在当前标签内导航。
- `target=_blank` / `window.open`：`supportMultipleWindows: true` + `onCreateWindow` 回调创建新标签，不交给系统。
- 工具栏另有"收藏当前页"按钮：直接用当前页标题 + 截图保存（不取附近图片），行为对齐扩展 popup 的"收好当前页面"。

### 6.3 视频全屏

- 使用插件回调 `onEnterFullscreen` / `onExitFullscreen`：
  - 进入：`SystemChrome.setEnabledSystemUIMode(immersiveSticky)`，允许横竖屏旋转，隐藏应用自己的工具栏。
  - 退出：恢复系统栏与方向，回到浏览器界面。
- Android `AndroidManifest.xml` 的 Activity 声明 `configChanges="orientation|screenSize|smallestScreenSize|keyboardHidden"`，避免旋转重建导致视频中断。
- `InAppWebViewSettings`：保持 `mediaPlaybackRequiresUserGesture` 默认（true），避免自动播放；`useHybridComposition` 使用默认（true）。
- 兜底：若个别站点用 `requestFullscreen()` 而非 `<video>` 全屏且 WebView 不接管，在 `inject.js` 里重写 `Element.prototype.requestFullscreen` 为 `callHandler('rl:fullscreen')`，由 Flutter 侧接管容器。该兜底在 M0 验证后再决定是否启用。
- v1 不引入任何播放器依赖。

### 6.4 WebView 安全设置

- `javaScriptEnabled: true`（业务需要）。
- `allowFileAccess: false`、`allowContentAccess: false`。
- `mixedContentMode: MIXED_CONTENT_NEVER_ALLOW`。
- `supportMultipleWindows: true`（用于标签拦截）。
- `javaScriptCanOpenWindowsAutomatically: false`。
- `safeBrowsingEnabled: true`。
- 不启用 `allowUniversalAccessFromFileURLs`。
- 证书：仅系统信任链，不忽略错误。

### 6.5 网页内注入脚本（`assets/js/inject.js`）

单一文件，`UserScript` 在 `AT_DOCUMENT_START` 注入到主框架（v1 只处理主框架）。

职责一：长按检测（移植 `entrypoints/content.ts` 逻辑）

```js
// 500ms、位移 > 10px 取消
// e.target.closest('a[href]') → 命中链接
// 触发后吞掉紧随的 click，避免菜单关闭后误跳转
window.flutter_inappwebview.callHandler('rl:longPress', {
  url, text, sourcePage: location.href, rect: {x, y, width, height}
});
```

职责二：页面内提取（移植 `utils/imageExtractor.ts` + `content.ts`）

```js
// 返回 JSON 字符串，供 Dart evaluateJavascript 调用
window.__rlExtract = async (url) => JSON.stringify({
  linkText, nearbyText, nearbyImage,   // base64 或 URL
});
```

- 图片优先级与扩展一致：链接内图片 → 父元素 → 相邻兄弟 → 上溯 3 层。
- `blob:` 图片在页面上下文 `fetch` → `FileReader` 转 base64（与扩展一致）；单图 > 5MB 放弃。
- 自定义 JS 提取器 v1 不开放编辑；`__rlExtract` 内部预留 `window.__rlCustomExtractor` 钩子，v1.1 再接设置页。

职责三：禁用系统长按菜单（配置层面尽量做，`inject.js` 只做兜底）

- 插件设置里关闭 Android 原生上下文菜单、iOS `allowsLinkPreview = false`。
- iOS 追加 CSS：`a[href] { -webkit-touch-callout: none; }`，避免 callout 与自绘菜单冲突。
- 该部分在 M0 于真机/模拟器逐项验证，验证不通过再升级为原生插件方案。

### 6.6 下载与文件选择（基础兜底）

- `onDownloadStartRequest`：v1 只提示"暂不支持下载"，v1.1 接 `DownloadManager`。
- 文件选择：使用插件内置 `onShowFileChooser` 能力，v1 用系统文件选择器。
- 权限（相机/麦克风/定位）：v1 不主动申请，站点触发时拒绝并提示。

## 7. 长按收藏（核心流程）

### 7.1 时序

```
用户长按链接
  → inject.js：识别 <a href>，callHandler('rl:longPress', {url, text, sourcePage})
  → Flutter：立即弹 LongPressSheet（加载态）
  → 并行：
      a) Dart evaluateJavascript(window.__rlExtract) → 标题文本/附近图片(base64)
      b) ApiClient.exists(url) → 是否已收藏
      c) TitleResolver：HTTP 拉目标页解析 <title>/og:title（5s 超时，失败回退）
  → Sheet 展示：链接、标题、缩略图、"已收藏"标记
  → 用户点"收藏到稍后再看"（第一项，主按钮）
      → controller.takeScreenshot() 取当前可见区域（JPEG 80）
      → POST /api/links（字段名见 5.1，snake_case）
      → 成功：SnackBar + "查看"；失败：可重试
```

### 7.2 菜单结构（顺序即产品要求）

```
┌─────────────────────────────────┐
│ ● 链接标题（最多两行）             │
│   example.com/a  ·  已收藏/未收藏  │
│ ─────────────────────────────── │
│ ★ 收藏到稍后再看        [主按钮]   │  ← 第一项
│ ☆ 收藏主站 example.com            │  ← 第二项
│ ↗ 在新标签打开                    │
│ ⧉ 复制链接                       │
│ ⤴ 分享                           │
│ 🌐 用系统浏览器打开                │
└─────────────────────────────────┘
```

- "收藏"必须在视觉与交互上都排最前；已收藏时默认禁用收藏按钮并提供"查看"入口（交互是否允许再次保存见 15.3）。
- 菜单项点击后关闭 sheet 再执行，避免平台视图与弹层竞争。

### 7.3 标题与图片规则

| 字段 | 来源 | 回退 |
| --- | --- | --- |
| `title` | 目标页 `<title>` / `og:title`（TitleResolver，带桌面 UA，5s 超时） | 链接 `title`/`aria-label` 文本 → 链接文字 → URL |
| `nearby_image` | 页面内提取（链接附近图） | 无 |
| `screenshot` | 当前页面可见区域截图 | 无（截图失败仅记日志，不阻塞保存） |
| `source_page` | 长按时页面 URL | 空字符串 |

- TitleResolver 直接 HTTP 拉目标页，不依赖页面加载；失败（超时/403/非 HTML）时静默回退，不阻塞收藏。
- 图片 base64 与截图总大小超过 8MB 时，先丢弃截图，再丢弃附近图片，并提示"图片过大已跳过"。
- 截图与图片都失败时仍允许收藏（与扩展行为一致）。

### 7.4 重复收藏

- Sheet 打开时查 `/api/links/exists`，命中则显示"已收藏"。
- v1 默认禁用收藏按钮（见 15.3）；若确认允许再次保存，则走同一 `POST /api/links`，按服务端结果提示，不在客户端拦截。

### 7.5 失败与离线

- 服务器未配置：Sheet 里直接显示"未配置服务器，去设置"。
- 网络失败：保留 Sheet 与已提取数据，提供"重试"；不排队、不落本地（v1 无离线队列）。

### 7.6 收藏当前页

- 工具栏"收藏当前页"复用同一保存链路：`title` 取 WebView 当前标题，`screenshot` 取当前可见区域，`nearby_image` 为空，`source_page` 为当前 URL。
- 同样先查 `exists`；已收藏时提示并给"查看"入口。

## 8. 链接库与设置

### 8.1 链接库

- 启动进入"收藏库"（不是空白浏览器）；点卡片或地址栏进入浏览器标签。
- 顶部：搜索框（300ms 防抖）、排序菜单（时间/标题）、视图切换（网格/列表）、回收站入口。
- 列表：分页加载（每页 50），滚动到底自动加载；图片用 `cached_network_image`，失败回退截图/占位。
- 点击：在新标签打开（若当前只有空白标签则复用）。
- 长按卡片：进入多选模式；v1 支持批量删除、批量还原（回收站内）。
- 删除：确认后 `DELETE /api/links/:id`，乐观更新 + 失败回滚。
- 回收站：两个 tab——"链接"用 `GET /api/trash`（全量取回、客户端本地分页），"站点"用 `GET /api/sites/trash`；两个 tab 都支持还原、永久删除（二次确认）。

### 8.2 设置

- 服务器地址、API Key、保存并测试连接（复用 `GET /api/health`）。
- 显示连接状态、服务器版本（`/api/stats` 可选）。
- 主题：跟随系统 / 浅色 / 深色。
- 浏览器：搜索源、清除缓存与 Cookie（`WebView` 的 `CookieManager` / `clearCache`）。
- 关于：版本号、API 契约说明、隐私说明（无统计上报）。
- "从平板浏览器导入标签页"入口：只展示 16 节的 adb 步骤说明与命令，不在 app 内执行。

### 8.3 平板布局

- 宽度 ≥ 600dp：`NavigationRail` + 内容区；地址栏与标签条同一行，标签条可横向滚动。
- 宽度 < 600dp（手机或分屏）：底部 `NavigationBar`，标签条折叠为标签数按钮。
- 横屏视频全屏时隐藏所有应用 UI。

### 8.4 站点页

- 与收藏库并列的独立 tab（导航条目：收藏 / 站点 / 浏览器 / 设置）。
- 网格卡片：图标 56dp（`icon_url` → `origin/favicon.ico` → 首字母占位）、名称（`title` → host）、host 小字。
- 点击：在新标签打开 origin；长按：删除（二次确认，进回收站）。
- 回收站：站点删除后进入回收站，入口在回收站页的"站点" tab；支持还原与永久删除。
- 空态引导："在网页里长按链接，选择'收藏主站'"。
- 数据来自 `GET /api/sites`，进入页面时刷新；删除乐观更新 + 失败回滚。

**收藏主站流程**：

1. 入口：长按 Sheet 第二项、浏览器工具栏菜单"收藏主站"。
2. `origin = scheme://host[:port]`（来自当前页或长按链接）；先 `GET /api/sites/exists?url=`。
3. TitleResolver 拉 origin 首页 HTML：取 `<title>` / `og:site_name` 作为名称；取 `<link rel="icon|shortcut icon">` 作为 `icon_url`（相对路径拼成绝对 URL），没有则回退 `origin/favicon.ico`。
4. `POST /api/sites`；已存在则提示"已收藏该站点"。
5. 当前页不是 http(s)（如 `about:blank`）时不显示"收藏主站"入口。

## 9. 安全与隐私

- API Key 只存 `flutter_secure_storage`，不写日志、不进崩溃上报（本项目无上报）。
- 自建服务器若为 `http://`：允许明文（`usesCleartextTraffic` 或 network security config 白名单），并在设置页提示"公网使用请启用 HTTPS"。
- 截图/图片只在收藏时读取，不后台常驻。
- Cookie 与站点数据由 WebView 管理；提供"清除浏览数据"。
- 不采集任何分析数据。

## 10. 错误处理与可观测性

- 统一 `AppLogger`：调试期 `debugPrint` 分级输出（`[ReadLater]` 前缀），生产构建关闭 debug 级。
- 关键路径日志：收藏（提取耗时、截图大小、请求结果）、WebView 回调、标签生命周期。
- 用户可见错误：SnackBar（可重试）/ 对话框（配置类）/ 页面空态（列表加载失败）。
- 崩溃：v1 不做上报，依赖 `flutter run` 与 `adb logcat`。

## 11. 测试策略

| 层级 | 内容 |
| --- | --- |
| 单元测试（`flutter test`） | ApiClient（含 sites，mock Dio）、错误映射、URL/origin 规范化、标题解析、分页去重合并 |
| Widget 测试 | 链接库空/加载/错误态、长按 Sheet 各状态、标签条交互、站点网格与空态、回收站双 tab |
| 集成测试（`integration_test` + Android 模拟器） | 本地 fixture 页面（`assets/test/` 经本地 HTTP 或 `initialFile` 加载）验证：长按回调、提取 JSON、截图、`addLink` 到本地服务器；收藏主站 → 站点页出现卡片 |
| 服务端（手动 curl） | `/api/sites`：正常增删查、401、重复收藏（活跃/回收站两种）、软删除、还原、永久删除、非法 url |
| 手工验收（平板真机） | B 站/YouTube 全屏与旋转、长按菜单置顶、多标签切换与返回键、截图质量、深色模式、横竖屏布局、站点卡片图标 |

- `inject.js` 的 DOM 逻辑用本地 fixture 页 + 集成测试覆盖；不额外引入 Node 测试栈。
- 每次发版前跑 `flutter analyze` + `flutter test`。

## 12. 构建与分发

- 包名：`com.cpf23333.readlater`（首次发布前可改，发布后不建议改）。
- 应用名：稍后再看。
- `minSdk 26`、`targetSdk` 跟随当前稳定版；`supports-screens` 允许 large/xlarge；`resizeableActivity=true`。
- 权限：`INTERNET`、`ACCESS_NETWORK_STATE`；不做后台服务。
- 签名：自建 keystore，`flutter build apk --release --split-per-abi`，侧载安装；个人自用不上架。
- 版本号跟 `mobile/pubspec.yaml` 的 `version`，与扩展/服务器版本独立（沿用 SemVer）。

## 13. 里程碑

| 阶段 | 内容 | 验收 |
| --- | --- | --- |
| M0 技术验证（2–3 天） | 空壳 + WebView + 2 标签切换 + 长按 JS 回调 + 截图 + `addLink` 打到真实服务器 + B 站全屏 | 13.1 各项全部跑通；确认 `IndexedStack + Offstage`、全屏、长按在真机可用 |
| M1 浏览器核心（约 1 周） | 地址栏、前进后退、标签条、标签会话、返回键、外链、全屏适配 | 平板日常浏览可用 |
| M2 收藏 + 链接库（约 1 周） | 长按 Sheet、提取、截图、标题、去重、保存；列表/搜索/排序/删除/回收站 | 长按收藏端到端可用 |
| M3 站点收藏（约 4 天） | 后端 `sites` 表与七个端点（含回收站）、站点页（网格/图标/删除进回收站）、回收站"站点"tab、"收藏主站"入口、标题与图标采集 | 收藏/打开/删除/还原/永久删除站点可用，后端 curl 用例通过 |
| M4 设置与打磨（约 3 天） | 服务器配置与测试、主题、清除数据、平板布局、错误态 | 可日常使用 |

> 标签页导入脚本、导入/导出、下载、系统分享入口等不在 v1 工期，统一记入 `todo.md`；其中标签页导入的设计保留在 16 节，随时可实施。

### 13.1 M0 必验清单

以下各项都是"设计依赖但尚未在真机确认"的平台行为，M0 逐项验证并记录结论：

1. `IndexedStack + Offstage` 下多个 `InAppWebView` 能保持页面存活、切换不白屏、返回不丢状态；5 个标签时的内存占用可接受。
2. 视频全屏：B 站/YouTube 点全屏后能横屏播放、退出恢复；`onEnterFullscreen`/`onExitFullscreen` 行为符合预期。
3. 长按：注入 JS 在真实站点能稳定命中链接；`disableContextMenu`/`allowsLinkPreview` 等设置能压掉系统菜单；长按后不会误触发点击跳转。
4. 截图：`takeScreenshot` 在当前 WebView 上返回正确图像，JPEG 压缩参数可用。
5. 收藏链路：本地服务器收到 `POST /api/links` 后图片落盘、列表可见。
6. `pause/resume`（后台标签）、`onCreateWindow`（新标签）、`onDownloadStartRequest` 的实际可用性与参数形态。

## 14. 风险与缓解

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| `IndexedStack + Offstage` 下多 WebView 内存偏高 | 多标签时卡顿/被系统杀 | 标签上限 10；后台标签暂停；M0 实测 5 个标签的内存表现 |
| 视频全屏在部分机型/站点异常 | 核心体验受损 | M0 用 B 站/YouTube 真机验证；必要时改用原生全屏容器或 JS 兜底 |
| 注入 JS 与页面自身长按逻辑冲突 | 菜单不弹/误触发 | 捕获阶段监听、位移阈值、触发后吞 click；M0 用多个站点抽测 |
| iOS 未来适配：WKWebView 无请求拦截、callout 限制 | 移植工作量 | 架构上把平台差异收敛到 `platform/`；v1 不承诺 iOS 行为完全一致 |
| 明文 HTTP 与自签证书 | 连接失败 | 设置页明确提示；文档给出 network security config 配置方法 |
| WebView 内核版本碎片化 | 个别站点渲染/播放异常 | 以平板真机为准；必要时提供 UA 切换兜底（v1.1） |
| 跨域 iframe 内的链接无法被注入脚本捕获 | 部分站点长按无菜单 | v1 明确只支持主框架；v1.1 用 Android 原生 hit-test 作为补充通道 |
| 站点收藏需要服务端改动 | 可能影响现有部署/数据 | 新增独立 `sites` 表与路由，不改现有接口与表；上线前备份 SQLite；服务端版本号 bump |
| 平板浏览器标签页只能靠 adb | 导入是手动流程，不是 app 功能 | 定位为一次性迁移工具；文档写清步骤；只支持 Chromium 系；不承诺自动化 |
| 无线调试端口变化 / adb forward 失效 | 导入脚本连不上 | 脚本先校验 `adb devices`，失败提示重新 forward；文档给无线调试完整步骤 |

## 15. 评审结论

2026-11-09 评审通过，以下按默认值执行：

1. 包名 `com.cpf23333.readlater`。
2. 批量删除/批量还原进 v1；导入/导出后置。
3. 已收藏时禁用收藏按钮 + 提供"查看"入口。
4. 服务器地址同时支持 `http://` 与 `https://`；内网 http 走明文配置并在设置页提示。
5. 地址栏搜索默认 Bing（设置页可改）。
6. 站点删除进回收站：`sites.deleted_at` 软删除，回收站页"站点"tab 还原/永久删除；重新收藏回收站中的站点会自动恢复。
7. 数据库保持 SQLite，不换 PostgreSQL；换库触发条件与优化项记入 `todo.md`。

追加需求（站点收藏、平板浏览器标签页导入）已并入 2.1、5.4、8.4、16；如与预期不符请指出。

## 16. 浏览器标签页导入（外部 adb 工具）

### 16.1 背景与结论

- 平板上的 Chrome/Brave 不向第三方 app 暴露"已打开标签页"，Android 沙箱下 app 内无法读取，没有合规 API。
- Chromium 系浏览器通过 abstract Unix socket `chrome_devtools_remote` 暴露 DevTools HTTP 端点，`adb forward` 后可取 `/json/list`（含每个标签页的 `url`、`title`）。
- 因此导入做成 PC 上运行的一次性脚本，不进 app UI；网络 adb 可行，但同样需要一台 PC/主机执行。

### 16.2 前置条件

- 平板：开发者选项 + USB 调试开启；Chrome/Brave 正在运行。
- 电脑：`platform-tools`（adb）、Node.js ≥ 20。
- 服务器：地址与 API Key（与 app 相同）。

### 16.3 步骤（USB）

```bash
adb devices
adb forward tcp:9222 localabstract:chrome_devtools_remote
# Brave 若上面连不上，先查实际 socket：
# adb shell cat /proc/net/unix | grep -i devtools
node tools/import-tabs/import.mjs \
  --server https://your-server \
  --api-key "$API_KEY" \
  [--socket chrome_devtools_remote] [--port 9222]
```

脚本行为：

1. `GET http://127.0.0.1:9222/json/list`，过滤 `type === "page"` 且 URL 为 http(s) 的条目。
2. 逐个 `GET /api/links/exists?url=` 去重（服务端批量插入不去重，必须在脚本侧过滤）。
3. `POST /api/links/batch`，每条带 `url`、`title`、`custom_data.importedFrom = "chromium-tabs"`；不传截图/图片。
4. 输出导入 / 跳过（已存在）/ 失败 统计；`--dry-run` 只打印不写库。

### 16.4 网络 adb

- Android 11+：开启"无线调试"，`adb pair <ip>:<pair-port>` 配对后 `adb connect <ip>:<port>`。
- 或先 USB 连一次：`adb tcpip 5555`，拔线后 `adb connect <ip>:5555`。
- 连接成功后 `adb forward` 用法不变；要求平板与电脑同一网络、平板休眠不断网。
- 注意：无线调试的端口在重启/重新配对后会变；`adb forward` 在 adb 重连后需要重新执行。

### 16.5 限制

- 只能导入当前打开的标签页（URL + 标题），没有截图和附近图片。
- Chrome/Brave 进程被杀后 socket 消失；需要保持浏览器在前台或后台运行。
- Firefox 不适用（调试协议不同）；仅 Chromium 系（Chrome、Brave、Edge 等，socket 名以实测为准）。
- 不含历史记录、书签、已关闭标签页。
- 这是开发/迁移工具，不随 app 分发。

### 16.6 备选方案（记录，不实现）

Chrome 开启"标签页同步"后，桌面扩展可用 `chrome.sessions.getDevices()` 读取其他设备打开的标签页并入库；仅 Chrome、需同一账号同步，Brave 不支持该能力。v1 不实现。

## 17. 与现有项目的关系

- `server/`：仅新增 `sites` 表与 `/api/sites` 路由组（7 个端点，含回收站），现有接口、数据表、部署方式不变；服务端版本号 bump。
- `entrypoints/`、`utils/`、`wxt.config.ts` 不动；v1 不要求扩展参与站点收藏或标签页导入，后续可选。
- 新增 `mobile/` 目录独立构建；根 `package.json` 不加脚本，避免污染扩展构建。
- 新增 `tools/import-tabs/`（独立 Node 脚本，不进任何构建产物）。
- 文档：完成后在 `AGENTS.md` 增加 mobile 章节与 `/api/sites` 说明、更新 `CHANGELOG.md`（实施阶段做）。
- 数据互通：两端共用同一服务器与 API，扩展端已有数据无需迁移。
