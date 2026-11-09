# ReadLater 移动端（Flutter）设计

- 日期：2026-11-09
- 状态：待评审
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
3. 长按链接：自绘菜单，"收藏到稍后再看"置顶；其余项：打开、新标签打开、复制链接、分享、用系统浏览器打开。
4. 收藏链路：标题（目标页 title/og:title，回退链接文字）、可见区域截图、链接附近图片（含 blob URL）、重复检测、保存到服务器。
5. 收藏当前页：工具栏按钮直接收藏当前页面（对应扩展 popup 的"收好当前页面"）。
6. 链接库：网格/列表、搜索、排序、分页、打开链接、删除（进回收站）、回收站还原/永久删除。
7. 设置：服务器地址、API Key、连接测试、主题跟随系统。
8. 长按菜单在 Android 与未来 iOS 上行为一致（不依赖系统 context menu）。

### 2.2 非目标（v1 不做）

- iOS 构建与适配（结构上预留，不实现）。
- 视频嗅探、自研播放器（Media3/ExoPlayer）、后台播放、画中画。
- 广告拦截、脚本拦截、下载管理器（下载仅做基础兜底，见 6.6）。
- 导入/导出、自定义 JS 提取器编辑、统计图表、标签系统。
- 离线缓存、增量同步、本地数据库（服务器仍是唯一数据源）。
- 系统分享入口（其他 app 分享链接到本 app），列为 v1.1。

## 3. 关键决策

| 决策 | 结论 | 理由 |
| --- | --- | --- |
| 框架 | Flutter 3.x（Dart 3） | 个人自用、Android 优先但保留 iPad 可能；UI 与逻辑一套代码；`flutter_inappwebview` 覆盖多标签、注入、截图、全屏视频 |
| 浏览器内核 | 系统 WebView（`flutter_inappwebview` 6.x） | 不引入 GeckoView/Cronet，平板场景够用；iOS 侧未来自动落到 WKWebView |
| 长按菜单触发 | 注入 JS 检测长按 + Flutter 自绘 bottom sheet | 菜单顺序 100% 可控；避开 iOS 系统 callout 顺序不可控的问题；与扩展 `content.ts` 逻辑同源 |
| 管理页实现 | Flutter 原生重写 | 若嵌 Vue 页面会引入双 UI 体系与 bridge，破坏 iOS 移植性；列表页功能虽多但不复杂 |
| 状态管理 | Riverpod（`flutter_riverpod`） | 依赖注入显式，API client / 配置 / tab 状态可测试；避免全局单例 |
| 导航 | `go_router` | 声明式路由，便于以后接 deep link |
| 数据源 | 现有 Hono 服务器，不改服务端 | 契约已稳定，扩展与 app 共用；去重、图片处理都在服务端 |
| 配置存储 | `flutter_secure_storage`（API Key、服务器地址、自定义配置） | Keystore 加密；个人自用不做多账号 |
| 主题 | Material 3，跟随系统，支持深色 | 与扩展视觉习惯一致即可，不做像素级复刻 |

## 4. 总体架构

```
┌────────────────────────────────────────────────────────┐
│ Flutter (Dart)                                          │
│                                                        │
│  UI 层        BrowserScreen / LibraryScreen / Settings  │
│               TabStrip / BrowserToolbar / LongPressSheet│
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
│ 现有 Hono + SQLite 服务器（server/，不改）                │
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

### 5.1 复用现有 API（服务端不改）

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
}
```

- 超时：普通请求 10s，`addLink` 30s（图片 base64 较大）。
- 错误分类：`NotConfigured`、`NetworkError`、`AuthError(401)`、`Validation(400)`、`ServerError(5xx)`，统一映射为可展示文案。
- 不自动重试 `addLink`；服务端本身按标准化 URL 去重，重复提交安全。
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
- 回收站：`GET /api/trash` 一次取回全部（数量不会太大），客户端本地分页展示；还原、永久删除（二次确认）。

### 8.2 设置

- 服务器地址、API Key、保存并测试连接（复用 `GET /api/health`）。
- 显示连接状态、服务器版本（`/api/stats` 可选）。
- 主题：跟随系统 / 浅色 / 深色。
- 浏览器：搜索源、清除缓存与 Cookie（`WebView` 的 `CookieManager` / `clearCache`）。
- 关于：版本号、API 契约说明、隐私说明（无统计上报）。

### 8.3 平板布局

- 宽度 ≥ 600dp：`NavigationRail` + 内容区；地址栏与标签条同一行，标签条可横向滚动。
- 宽度 < 600dp（手机或分屏）：底部 `NavigationBar`，标签条折叠为标签数按钮。
- 横屏视频全屏时隐藏所有应用 UI。

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
| 单元测试（`flutter test`） | ApiClient（mock Dio）、错误映射、URL 规范化、标题解析、分页去重合并 |
| Widget 测试 | 链接库空/加载/错误态、长按 Sheet 各状态、标签条交互 |
| 集成测试（`integration_test` + Android 模拟器） | 本地 fixture 页面（`assets/test/` 经本地 HTTP 或 `initialFile` 加载）验证：长按回调、提取 JSON、截图、`addLink` 到本地服务器 |
| 手工验收（平板真机） | B 站/YouTube 全屏与旋转、长按菜单置顶、多标签切换与返回键、截图质量、深色模式、横竖屏布局 |

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
| M3 设置与打磨（约 1 周） | 服务器配置与测试、主题、清除数据、平板布局、错误态 | 可日常使用 |
| M4（可选） | 导入/导出、标签恢复细节、下载、系统分享入口 | 按需 |

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

## 15. 待确认事项

1. **包名**：`com.cpf23333.readlater` 是否可以（发布后再改会丢升级路径）。
2. **链接库 v1 范围**：批量删除/批量还原按"进 v1"设计，导入/导出后置，是否同意？
3. **已收藏时的交互**：默认"禁用收藏按钮 + 查看入口"，还是允许再次保存？
4. **服务器访问方式**：平板访问的是内网 `http://` 还是公网 `https://`（决定明文配置与证书说明）。
5. **应用内搜索源**：默认 Bing 是否可接受（国内网络可换）。

## 16. 与现有项目的关系

- `server/` 不改；`entrypoints/`、`utils/`、`wxt.config.ts` 不动。
- 新增 `mobile/` 目录独立构建；根 `package.json` 不加脚本，避免污染扩展构建。
- 文档：完成后在 `AGENTS.md` 增加 mobile 章节、更新 `CHANGELOG.md`（实施阶段做）。
- 数据互通：两端共用同一服务器与 API，扩展端已有数据无需迁移。
