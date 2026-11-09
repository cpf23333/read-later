# ReadLater Mobile v1 (Flutter) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付一个 Android 平板 app：内置浏览器（多标签、网页视频全屏、长按链接弹菜单且"收藏到稍后再看"置顶）、收藏库、站点页（含回收站）、设置；数据全部走现有自建服务器。

**Architecture:** Flutter + `flutter_inappwebview`（系统 WebView）+ Riverpod + go_router。浏览器长按由注入脚本 `assets/js/inject.js` 检测并通过 JS handler 回调 Dart，菜单用 Flutter 自绘；收藏链路在页面上下文取标题/附近图片、用 WebView 截图，POST 到现有 `/api/links`；站点走本仓库另一份计划 `2026-11-09-server-sites-api.md` 新增的 `/api/sites`。

**Tech Stack:** Flutter 3.x / Dart 3、flutter_inappwebview 6.x、flutter_riverpod 2.x、go_router、Dio、flutter_secure_storage、shared_preferences、cached_network_image、url_launcher、share_plus、logger、package:html；测试用 flutter_test、integration_test、http_mock_adapter、fake_async。

**Spec:** `docs/superpowers/specs/2026-11-09-readlater-mobile-flutter-design.md`

**Plan dependency:** Task 3 的 `ApiClient` 站点方法、Task 13 依赖 `docs/superpowers/plans/2026-11-09-server-sites-api.md` 的 Task 1 已完成（或至少服务器已运行新版本）。其余任务可先做。

## Global Constraints

- Android only（v1 不写 iOS 代码）；包名 `com.cpf23333.readlater`；应用名"稍后再看"；`minSdk 26`。
- 浏览器内核只用系统 WebView（`flutter_inappwebview` 6.x）；不引入 GeckoView/Cronet。
- 不引入播放器依赖（Media3/ExoPlayer/VideoPlayer），不实现视频嗅探、广告拦截、离线缓存、本地数据库。
- 服务器是唯一数据源；不改动现有服务器端点；站点接口契约见 spec 5.4。
- 收藏请求体字段一律 snake_case：`nearby_image`、`screenshot`、`source_page`、`custom_data`；鉴权头 `Authorization: Bearer <API_KEY>`。
- 超时：普通请求 10s；`POST /api/links` 30s。
- 长按菜单顺序固定：第 1 项"收藏到稍后再看"，第 2 项"收藏主站"。
- 图片上限：单张附近图片 > 5MB 丢弃；截图 + 图片总大小 > 8MB 时先丢截图、再丢图片。
- API Key 只存 `flutter_secure_storage`，不写日志。
- 每个任务结束提交一次；提交信息用 `feat:`/`test:`/`chore:`/`docs:` 前缀。

## Review Focus

1. **长按误触与手势冲突**：页面滚动、轻微滑动、短按不应弹菜单；菜单关闭后不能误触发链接跳转；iframe 内链接 v1 不支持（必须明确不崩）。
2. **多标签与旋转/返回键**：切 tab 不丢页面状态；视频全屏退出后工具栏与系统栏恢复；后台标签暂停；返回键先网页后退再关标签。
3. **截图/图片超时或过大**：收藏仍应成功、提示准确、UI 不被 30s 请求卡死（加载态 + 可重试）。
4. **服务器未配置 / 401 / 断网**：长按 Sheet 可重试、设置入口可达、任何路径不崩溃。
5. **站点回收站边界**：回收站中的站点再次收藏自动恢复；`http://a.com:8080` 与 `https://a.com` 不同 origin；永久删除后重新收藏生成新记录。

---

### Task 0: 脚手架与依赖

**Files:**
- Create: `mobile/`（由 `flutter create` 生成）
- Modify: `mobile/pubspec.yaml`

**Interfaces:**
- Consumes: 无。
- Produces: 可运行的空 Flutter 工程；后续任务的全部依赖可用。

- [ ] **Step 1: 生成工程**

```bash
cd /path/to/read-later
flutter create --org com.cpf23333 --project-name readlater --platforms=android mobile
```

- [ ] **Step 2: 配置依赖与资源**

`mobile/pubspec.yaml` 的 `dependencies` 增加（版本以 pub 最新兼容为准，不跨大版本）：

```yaml
flutter_inappwebview: ^6.1.5
flutter_riverpod: ^2.6.1
go_router: ^14.6.2
dio: ^5.7.0
flutter_secure_storage: ^9.2.2
shared_preferences: ^2.3.3
cached_network_image: ^3.4.1
url_launcher: ^6.3.1
share_plus: ^10.1.2
logger: ^2.5.0
html: ^0.15.5
```

`dev_dependencies` 增加：

```yaml
http_mock_adapter: ^0.6.1
fake_async: ^1.3.1
integration_test:
  sdk: flutter
```

`flutter:` 段增加：

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/js/
    - assets/test/
```

创建空目录 `mobile/assets/js/`、`mobile/assets/test/`（各放一个 `.gitkeep`）。

- [ ] **Step 3: 验证基线**

```bash
cd mobile
flutter pub get
flutter analyze
flutter test
```

Expected: 0 error；默认 widget test 通过。

- [ ] **Step 4: 提交**

```bash
git add mobile
git commit -m "chore(mobile): 初始化 Flutter 工程与依赖"
```

---

### Task 1: 核心模型、错误类型、origin 工具

**Files:**
- Create: `mobile/lib/core/models/link.dart`、`site.dart`、`config.dart`、`health.dart`
- Create: `mobile/lib/core/api/errors.dart`
- Create: `mobile/lib/core/util/origin.dart`
- Test: `mobile/test/core/origin_test.dart`、`mobile/test/core/models_test.dart`

**Interfaces:**
- Consumes: 无。
- Produces:
  - `String? originOf(String url)`、`String? hostOf(String url)`
  - `class ServerConfig { String baseUrl; String apiKey; bool enabled; }`
  - `class LinkItem { id, url, title, nearbyImage, screenshot, sourcePage, createdAt, customData }` + `fromJson`
  - `class PagedLinks { List<LinkItem> links; int total; }`
  - `class TrashItem { id, linkId, url, title, nearbyImage, screenshot, sourcePage, createdAt, deletedAt }`
  - `class Site { id, url, title, iconUrl, createdAt }` + `fromJson`
  - `class SiteInput { String url; String title; String? iconUrl; }`
  - `class SiteExistsResult { bool exists; bool inTrash; }`
  - `class HealthStatus { bool ok; }`
  - `class AddLinkRequest { ..., Map<String, Object?> toJson() }`
  - `sealed class ApiException` 及子类 `NotConfiguredException`、`NetworkException`、`AuthException`、`ValidationException`、`ServerException`

- [ ] **Step 1: 先写失败测试**

```dart
// test/core/origin_test.dart
test('originOf 保留 scheme/host/port，去掉 path/query/fragment', () {
  expect(originOf('https://example.com/a?b=1#c'), 'https://example.com');
  expect(originOf('http://example.com:8080/x'), 'http://example.com:8080');
});
test('originOf 对非 http(s) 返回 null', () {
  expect(originOf('about:blank'), isNull);
  expect(originOf('not a url'), isNull);
});
```

```dart
// test/core/models_test.dart
test('Site.fromJson 解析 icon_url 与时间', () {
  final s = Site.fromJson({
    'id': '1', 'url': 'https://a.com', 'title': 'A',
    'icon_url': null, 'created_at': 100,
  });
  expect(s.url, 'https://a.com');
  expect(s.iconUrl, isNull);
  expect(s.createdAt, 100);
});
test('AddLinkRequest.toJson 使用 snake_case', () {
  final req = AddLinkRequest(
    url: 'https://a.com', title: 'A',
    nearbyImage: 'data:x', screenshot: 'data:y',
    sourcePage: 'https://b.com', customData: {'linkText': 't'},
  );
  expect(req.toJson().keys, containsAll(['nearby_image', 'screenshot', 'source_page', 'custom_data']));
  expect(req.toJson()['nearby_image'], 'data:x');
});
```

Run: `cd mobile && flutter test test/core/origin_test.dart` → FAIL（文件/函数不存在）。

- [ ] **Step 2: 实现**

`origin.dart`：`Uri.tryParse`，仅 `http`/`https` 且有 host 时返回 `Uri(scheme:, host:, port:).origin`；`hostOf` 返回 `uri.host`。
`models`：全部 `final` 字段 + `fromJson`（服务器字段为 snake_case，时间戳 int 毫秒）。`AddLinkRequest.toJson()` 输出上表字段，`null` 字段可省略。
`errors.dart`：`sealed class ApiException implements Exception { final String message; }`，子类无额外字段。

- [ ] **Step 3: 验证并提交**

```bash
cd mobile
flutter test test/core
flutter analyze
git add lib/core test/core
git commit -m "feat(mobile): 核心模型与 origin 工具"
```

---

### Task 2: 配置存储（KeyValueStore + ConfigStore）

**Files:**
- Create: `mobile/lib/core/config/key_value_store.dart`、`config_store.dart`
- Create: `mobile/test/support/fakes.dart`（`InMemoryKeyValueStore`、后续 `FakeApiClient` 都放这里）
- Test: `mobile/test/core/config_store_test.dart`

**Interfaces:**
- Consumes: `ServerConfig`（Task 1）。
- Produces:
  - `abstract class KeyValueStore { Future<String?> read(String key); Future<void> write(String key, String value); Future<void> delete(String key); }`
  - `class SecureKeyValueStore implements KeyValueStore`（包 `FlutterSecureStorage`）
  - `class InMemoryKeyValueStore implements KeyValueStore`（测试用，放 `test/support/`）
  - `class ConfigStore { Future<ServerConfig> read(); Future<void> save(ServerConfig config); Future<bool> isConfigured(); }`
  - 存储 key：`server_config`，值为 `{"baseUrl":"...","apiKey":"...","enabled":true}`。

- [ ] **Step 1: 写失败测试**

```dart
test('未保存时返回禁用配置', () async {
  final store = ConfigStore(InMemoryKeyValueStore());
  final cfg = await store.read();
  expect(cfg.enabled, isFalse);
  expect(cfg.baseUrl, isEmpty);
});
test('保存时去掉 baseUrl 末尾斜杠并可读回', () async {
  final store = ConfigStore(InMemoryKeyValueStore());
  await store.save(ServerConfig(baseUrl: 'http://192.168.1.2:3000/', apiKey: 'k', enabled: true));
  final cfg = await store.read();
  expect(cfg.baseUrl, 'http://192.168.1.2:3000');
  expect(await store.isConfigured(), isTrue);
});
```

- [ ] **Step 2: 实现并验证**

`ConfigStore.save` 用 `jsonEncode` 写入；`read` 解析失败时回退默认值（不抛异常）。`isConfigured` = `enabled && baseUrl.isNotEmpty && apiKey.isNotEmpty`。

Run: `flutter test test/core/config_store_test.dart` → PASS；`flutter analyze`。

- [ ] **Step 3: 提交**

```bash
git add lib/core/config test/core/config_store_test.dart test/support
git commit -m "feat(mobile): 服务器配置存储"
```

---

### Task 3: ApiClient（Dio）

**Files:**
- Create: `mobile/lib/core/api/api_client.dart`（抽象接口 + `ExistsResult`）
- Create: `mobile/lib/core/api/dio_api_client.dart`
- Create: `mobile/lib/providers.dart`（本任务先放 `configStoreProvider`、`apiClientProvider`）
- Modify: `mobile/test/support/fakes.dart`（追加 `FakeApiClient`：实现全部方法，默认返回空值，可注入异常）
- Test: `mobile/test/core/api_client_test.dart`

**Interfaces:**
- Consumes: `ServerConfig`/`ConfigStore`、模型与错误类型、`AddLinkRequest`。
- Produces:
  - `abstract class ApiClient`：
    `health()`、`linkExists(String url)`、`addLink(AddLinkRequest)`、`listLinks({page,pageSize,search,domain,sortBy,sortOrder})`、`deleteLink(id)`、`listTrash()`、`restoreTrash(id)`、`purgeTrash(id)`、`listSites()`、`addSite(SiteInput)`、`deleteSite(id)`、`listSiteTrash()`、`restoreSite(id)`、`purgeSite(id)`、`siteExists(String url)`。
    `siteExists` 返回 `SiteExistsResult`；`linkExists` 返回 `ExistsResult { bool exists; LinkItem? link; }`。
  - `class DioApiClient implements ApiClient { DioApiClient(Dio dio, ConfigStore configStore); }`
  - 方法签名（完整）：`Future<HealthStatus> health()`、`Future<ExistsResult> linkExists(String url)`、`Future<void> addLink(AddLinkRequest req)`、`Future<PagedLinks> listLinks({int page = 1, int pageSize = 50, String? search, String? domain, String sortBy = 'created_at', String sortOrder = 'desc'})`、`Future<void> deleteLink(String id)`、`Future<List<TrashItem>> listTrash()`、`Future<void> restoreTrash(String id)`、`Future<void> purgeTrash(String id)`、`Future<List<Site>> listSites()`、`Future<Site> addSite(SiteInput input)`、`Future<void> deleteSite(String id)`、`Future<List<Site>> listSiteTrash()`、`Future<void> restoreSite(String id)`、`Future<void> purgeSite(String id)`、`Future<SiteExistsResult> siteExists(String url)`。
  - Provider：`final configStoreProvider = Provider<ConfigStore>((ref) => ConfigStore(SecureKeyValueStore()));`、`final apiClientProvider = Provider<ApiClient>((ref) => DioApiClient(Dio(), ref.watch(configStoreProvider)));`
  - 测试辅助：`ConfigStore _configStore({required String baseUrl, required String apiKey})` 在 `test/support/fakes.dart` 中用 `InMemoryKeyValueStore` 预置配置。
- [ ] **Step 1: 写失败测试（DioAdapter）**

```dart
test('listLinks 解析 data 与 total，并带 Bearer 头', () async {
  final dio = Dio();
  final adapter = DioAdapter(dio: dio);
  adapter.onGet('http://s/api/links?page=1&pageSize=50&sortBy=created_at&sortOrder=desc',
    (server) => server.reply(200, {'success': true, 'data': [
      {'id': '1', 'url': 'https://a.com', 'title': 'A', 'created_at': 1}
    ], 'total': 1}),
    headers: {'Authorization': 'Bearer k'});
  final client = DioApiClient(dio, _configStore(baseUrl: 'http://s', apiKey: 'k'));
  final page = await client.listLinks();
  expect(page.total, 1);
  expect(page.links.single.title, 'A');
});
test('401 映射为 AuthException', () async {
  // reply 401 → expect(client.listLinks(), throwsA(isA<AuthException>()))
});
test('未配置时抛 NotConfiguredException', () async {
  // ConfigStore 默认空 → expect(client.listSites(), throwsA(isA<NotConfiguredException>()))
});
test('addLink 发送 snake_case body', () async {
  // adapter.onPost('http://s/api/links', (server) => server.reply(200, {'success': true}),
  //   data: containsPair('nearby_image', 'data:x'));
});
test('siteExists 解析 inTrash', () async {
  // reply {'success': true, 'data': {'exists': false, 'inTrash': true}}
  // expect((await client.siteExists('https://a.com')).inTrash, isTrue);
});
```

- [ ] **Step 2: 实现**

- 每次请求先 `configStore.read()`；未配置 → `NotConfiguredException`。
- URL 拼接 `'${cfg.baseUrl}$path'`；查询参数用 `queryParameters`。
- `DioException` 映射：`connectionTimeout/receiveTimeout/sendTimeout` → `NetworkException`；`badResponse` 401 → `AuthException`；400 → `ValidationException`；5xx → `ServerException`；其余 → `NetworkException`。
- 超时：普通请求 10s；`addLink` 30s。
- `listLinks` 的 `sortBy` 默认 `created_at`、`sortOrder` 默认 `desc`、`pageSize` 默认 50。
- `addLink` body 用 `AddLinkRequest.toJson()`。
- `siteExists` 调 `GET /api/sites/exists?url=`。

- [ ] **Step 3: 验证并提交**

```bash
flutter test test/core/api_client_test.dart
flutter analyze
git add lib/core/api lib/providers.dart test/core/api_client_test.dart
git commit -m "feat(mobile): API 客户端"
```

---

### Task 4: App 外壳（主题、路由、平板自适应导航）

**Files:**
- Create: `mobile/lib/main.dart`、`app.dart`、`router.dart`
- Create: 占位页 `mobile/lib/features/library/library_screen.dart`、`sites/sites_screen.dart`、`browser/browser_screen.dart`、`settings/settings_screen.dart`（先只显示标题文本）
- Create: `mobile/lib/shared/widgets/adaptive_scaffold.dart`
- Create: `mobile/lib/core/logging/app_logger.dart`（`logger` 包封装：`AppLogger.d/i/w/e`，统一 `[ReadLater]` 前缀；release 只输出 warn/error）
- Delete: `mobile/test/widget_test.dart`（模板测试，由 `app_shell_test.dart` 取代）
- Test: `mobile/test/app_shell_test.dart`

**Interfaces:**
- Consumes: Riverpod、go_router。
- Produces:
  - `main()` 内 `ProviderScope` + `runApp(const ReadLaterApp())`。
  - 路由：`/library`、`/sites`、`/browser`、`/settings`，用 `StatefulShellRoute.indexedStack` 保活各分支。
  - `AdaptiveScaffold`：接收 `StatefulNavigationShell`，宽度 ≥ 600dp 用 `NavigationRail`，否则 `NavigationBar`；`onDestinationSelected` 调 `navigationShell.goBranch(index)`；4 个 destination：收藏、站点、浏览器、设置。
  - 主题：Material 3，`ColorScheme.fromSeed`，支持浅色/深色/跟随系统（`themeMode` 先用系统默认，Task 14 接设置）。

- [ ] **Step 1: 写失败测试**

```dart
testWidgets('渲染 4 个导航目的地，默认在收藏库', (tester) async {
  await tester.pumpWidget(const ProviderScope(child: ReadLaterApp()));
  await tester.pumpAndSettle();
  expect(find.text('收藏'), findsOneWidget);
  expect(find.text('站点'), findsOneWidget);
  expect(find.text('浏览器'), findsOneWidget);
  expect(find.text('设置'), findsOneWidget);
});
testWidgets('点击浏览器切换到浏览器占位页', (tester) async { ... expect(find.text('浏览器占位'), findsOneWidget); });
```

- [ ] **Step 2: 实现并验证**

占位页用 `Scaffold(appBar: AppBar(title: Text('浏览器占位')))`；`AdaptiveScaffold` 由 shell 使用。测试可设置 `tester.view.physicalSize = Size(1200, 900)` 验证 rail 布局。

```bash
flutter test test/app_shell_test.dart
flutter analyze
git add lib test/app_shell_test.dart
git commit -m "feat(mobile): 应用外壳与平板自适应导航"
```

---

### Task 5: 浏览器状态（标签、注册表、会话）

**Files:**
- Create: `mobile/lib/features/browser/browser_state.dart`、`browser_notifier.dart`、`tab_registry.dart`
- Create: `mobile/lib/core/storage/session_store.dart`
- Modify: `mobile/test/support/fakes.dart`（追加 `InMemorySessionStore`）
- Test: `mobile/test/features/browser_notifier_test.dart`
- Modify: `mobile/lib/providers.dart`（`browserProvider`、`tabRegistryProvider`、`sessionStoreProvider`）

**Interfaces:**
- Consumes: Riverpod。
- Produces:
  - `class BrowserTab { final String id; final String url; final String title; final String? favicon; final bool loading; final bool canGoBack; final bool canGoForward; }` + `copyWith`
  - `class BrowserState { final List<BrowserTab> tabs; final String? activeTabId; BrowserTab? get activeTab; }`
  - `class BrowserNotifier extends Notifier<BrowserState>`：
    - `void openTab(String url, {bool activate = true})`（超过 10 个标签关闭最久未使用的非活动标签；禁止空 url）
    - `void closeTab(String id)`（关闭最后一个标签时保留一个空白 `about:blank` 标签）
    - `void activate(String id)`
    - `void updateTab(String id, {String? url, String? title, String? favicon, bool? loading, bool? canGoBack, bool? canGoForward})`
    - `void initialize(List<String> urls, String? activeUrl)`
  - `class TabRegistry { void register(String tabId, InAppWebViewController c); void unregister(String tabId); InAppWebViewController? of(String tabId); }`
  - `abstract class SessionStore { Future<SessionData?> load(); Future<void> save(SessionData data); }`，`SessionData { List<String> urls; String? activeUrl; }`；`SharedPreferencesSessionStore` 实现；`InMemorySessionStore` 供测试。
  - 变更后 300ms 防抖写入 SessionStore（`Timer`）。
  - `BrowserNotifier` 无构造参数，依赖通过 `ref.read(sessionStoreProvider)` 获取（便于测试用 `ProviderContainer` 覆盖）。

- [ ] **Step 1: 写失败测试**

```dart
test('openTab 激活新标签并保留旧标签', () {
  final container = ProviderContainer(overrides: [
    sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
  ]);
  final n = container.read(browserProvider.notifier);
  n.openTab('https://a.com');
  n.openTab('https://b.com');
  expect(n.state.tabs.length, 2);
  expect(n.state.activeTab?.url, 'https://b.com');
});
test('超过 10 个标签时关闭最久未使用的非活动标签', () { ... expect(n.state.tabs.length, 10); });
test('关闭最后一个标签后保留 about:blank', () { ... expect(n.state.tabs.single.url, 'about:blank'); });
test('标签变化 300ms 后写入会话', () => fakeAsync((async) { n.openTab('https://a.com'); async.elapse(Duration(milliseconds: 350)); expect(fakeSession.saved, isNotNull); }));
```

- [ ] **Step 2: 实现并验证**

`BrowserNotifier` 用 `Notifier<BrowserState>`；`build()` 返回 `tabs: [BrowserTab(id: uuid, url: 'about:blank')]`。id 用 `DateTime.now().microsecondsSinceEpoch + counter`（不引第三方 uuid 包）。`TabRegistry` 用普通 `Map<String, InAppWebViewController>`，provider 里 `Provider<TabRegistry>((ref) => TabRegistry())`。

```bash
flutter test test/features/browser_notifier_test.dart
flutter analyze
git add lib/features/browser lib/core/storage lib/providers.dart test
git commit -m "feat(mobile): 多标签状态与会话持久化"
```

---

### Task 6: 浏览器 UI（WebView、地址栏、标签条、全屏、外链）

**Files:**
- Create: `mobile/lib/features/browser/browser_screen.dart`（替换占位）
- Create: `mobile/lib/features/browser/tab_webview.dart`、`browser_toolbar.dart`、`tab_strip.dart`
- Create: `mobile/lib/platform/webview_settings.dart`、`mobile/lib/platform/system_ui.dart`
- Test: `mobile/test/features/browser_toolbar_test.dart`

**Interfaces:**
- Consumes: `BrowserNotifier`、`TabRegistry`、`SessionStore`。
- Produces:
  - `InAppWebViewSettings buildWebViewSettings({required bool isAndroid})`：`javaScriptEnabled: true`、`supportMultipleWindows: true`、`javaScriptCanOpenWindowsAutomatically: false`、`allowFileAccess: false`、`allowContentAccess: false`、`mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW`、`safeBrowsingEnabled: true`、`useShouldOverrideUrlLoading: true`、`isInspectable: kDebugMode`。
  - `void enterFullscreen()` / `Future<void> exitFullscreen()`：沉浸式 + 允许旋转 / 恢复系统栏与竖屏。
  - `BrowserToolbar`：参数 `url`、`canGoBack`、`canGoForward`、`loading`、`onNavigate(String)`、`onBack`、`onForward`、`onReload`、`onStop`、`onCollectPage`、`onMenu`。
  - `TabStrip`：标签横向滚动、当前标签高亮、点按切换、关闭按钮、新建标签按钮。
  - `TabWebView`：参数 `tab`、`onCreated(controller)`、`onLongPressLink(LinkPressPayload)`（本任务先传空实现，Task 7 接注入）、`onExternalScheme(String)`。
  - `LinkPressPayload { String url; String? text; String sourcePage; }`

- [ ] **Step 1: 写工具栏 widget 测试**

```dart
testWidgets('地址栏显示当前 URL，提交触发 onNavigate', (tester) async {
  String? navigated;
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: BrowserToolbar(
    url: 'https://a.com', canGoBack: false, canGoForward: false, loading: false,
    onNavigate: (v) => navigated = v, onBack: () {}, onForward: () {},
    onReload: () {}, onStop: () {}, onCollectPage: () {}, onMenu: () {},
  ))));
  expect(find.text('https://a.com'), findsOneWidget);
  await tester.enterText(find.byType(TextField), 'example.com');
  await tester.testTextInput.receiveAction(TextInputAction.go);
  expect(navigated, 'https://example.com'); // 无 scheme 自动补 https://
});
```

- [ ] **Step 2: 实现浏览器 UI**

- `BrowserScreen`：从 `browserProvider` 取 tabs/active；`IndexedStack` + `Offstage` 渲染每个 `TabWebView`（懒创建：只在 `tab.url != 'about:blank'` 时构造 WebView；空标签显示新标签页占位）；顶部 `BrowserToolbar` + `TabStrip`。
- `TabWebView` 回调更新 `BrowserNotifier`：`onLoadStart` loading=true、`onLoadStop` loading=false + URL/标题、`onUpdateVisitedHistory` 更新 url 与 canGoBack/canGoForward、`onReceivedError` 停止 loading。
- `onCreateWindow`：创建新标签并 `loadUrl`（返回 true 拦截系统）。
- 非 http(s) scheme：`onNavigationRequest` 里若 `url` 不是 http/https/about 则 `url_launcher` 打开并返回 `CANCEL`。
- 全屏：`onEnterFullscreen: () => enterFullscreen()`、`onExitFullscreen: () => exitFullscreen()`（回调名与签名以插件版本文档为准；行为不变）。
- 文件选择走插件内置 `onShowFileChooser` 默认实现；相机/麦克风/定位等权限请求在 `onPermissionRequest` 中直接拒绝并 SnackBar 提示（v1 不主动申请）。
- `onDownloadStartRequest`：仅 SnackBar 提示"暂不支持下载"。
- `TabRegistry` 注册与注销放在 `onWebViewCreated` / dispose。
- 返回键：`BrowserScreen` 用 `PopScope(canPop: false)`，按 canGoBack → goBack；否则 closeTab；否则 `SystemNavigator.pop()`。

- [ ] **Step 3: 验证并提交**

```bash
flutter test test/features/browser_toolbar_test.dart
flutter analyze
flutter run -d <tablet-device>   # 手动：打开 2 个标签切换、点全屏视频
git add lib test
git commit -m "feat(mobile): 内置浏览器界面与多标签"
```

---

### Task 7: 注入脚本 inject.js 与长按桥接

**Files:**
- Create: `mobile/assets/js/inject.js`
- Create: `mobile/assets/test/fixture.html`
- Create: `mobile/lib/features/browser/inject_loader.dart`（`Future<String> loadInjectJs(AssetBundle)`）
- Modify: `mobile/lib/features/browser/tab_webview.dart`（`initialUserScripts` + `addJavaScriptHandler`）
- Test: `mobile/integration_test/long_press_test.dart`

**Interfaces:**
- Consumes: `LinkPressPayload`（Task 6）。
- Produces:
  - JS handler：`rl:longPress`，参数 `{ url, text, sourcePage }`。
  - JS 全局：`window.__rlExtract(url)` → Promise\<JSON string\>，字段 `{ linkText, nearbyText, nearbyImage }`。
  - JS 测试钩子：`window.__rlTestLongPress(selector)`。
  - `loadInjectJs` 读取 `assets/js/inject.js` 原文。

- [ ] **Step 1: 写注入脚本**

`inject.js`（纯 IIFE，防重复注入；`window.__rlInjected` 标记）：

- `touchstart`（capture, passive）：记录起点坐标、目标元素、启动 500ms 定时器；`touchend`/`touchmove` 取消（位移 > 10px 取消）。
- 定时器触发时：`target.closest('a[href]')`，URL 仅接受 `http(s)`；调用 `window.flutter_inappwebview.callHandler('rl:longPress', {url, text, sourcePage: location.href})`；置 `suppressClick = true`。
- 触发后的第一次 `click`（capture）`preventDefault()` + `stopPropagation()`，然后复位，避免菜单关闭后误跳转。
- `window.__rlExtract = async (url) => { ... JSON.stringify({linkText, nearbyText, nearbyImage}) }`：
  - 图片按扩展同款优先级找（链接内 img → 父元素 → 相邻兄弟 → 上溯 3 层）。
  - `blob:` 用 `fetch + FileReader` 转 data URL；> 5MB 放弃；`data:` 直接返回。
- 追加样式：`a[href] { -webkit-touch-callout: none; }`（iOS 兼容用，Android 无害）。
- `window.__rlTestLongPress = (sel) => { const a = document.querySelector(sel); ... 直接调 handler; }`。

`fixture.html`：一个 `<a id="link" href="https://example.com/article">文章</a>` + 一个 `<img src="data:image/png;base64,...">` 的父容器。

- [ ] **Step 2: 接入 TabWebView**

```dart
final injectJs = await loadInjectJs(rootBundle);
InAppWebView(
  initialUrlRequest: URLRequest(url: WebUri(tab.url)),
  initialSettings: buildWebViewSettings(isAndroid: true),
  initialUserScripts: UnmodifiableListView([
    UserScript(source: injectJs, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START, forMainFrameOnly: true),
  ]),
  onWebViewCreated: (controller) {
    registry.register(tab.id, controller);
    controller.addJavaScriptHandler(handlerName: 'rl:longPress', callback: (args) {
      final m = args.first as Map;
      onLongPressLink(LinkPressPayload(url: m['url'] as String, text: m['text'] as String?, sourcePage: m['sourcePage'] as String));
      return null;
    });
  },
)
```

- [ ] **Step 3: 写集成测试**

```dart
// integration_test/long_press_test.dart
// 文件顶部：IntegrationTestWidgetsFlutterBinding.ensureInitialized();
testWidgets('fixture 页面：长按钩子回调 URL，提取返回 JSON', (tester) async {
  final payloads = <Map>[];
  final injectJs = await loadInjectJs(rootBundle);
  late InAppWebViewController controller;
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: InAppWebView(
    initialFile: 'assets/test/fixture.html',
    initialSettings: InAppWebViewSettings(javaScriptEnabled: true),
    initialUserScripts: UnmodifiableListView([UserScript(source: injectJs, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START, forMainFrameOnly: true)]),
    onWebViewCreated: (c) {
      controller = c;
      c.addJavaScriptHandler(handlerName: 'rl:longPress', callback: (args) { payloads.add(args.first as Map); return null; });
    },
  ))));
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  await controller.evaluateJavascript(source: "window.__rlTestLongPress('#link')");
  await tester.pumpAndSettle();
  expect(payloads.single['url'], 'https://example.com/article');
  final extracted = await controller.evaluateJavascript(source: "window.__rlExtract('https://example.com/article')");
  expect((jsonDecode(extracted as String) as Map)['linkText'], '文章');
});
```

- [ ] **Step 4: 运行并提交**

```bash
cd mobile
flutter analyze
flutter test integration_test/long_press_test.dart -d <device-id>
git add assets lib integration_test
git commit -m "feat(mobile): 长按注入脚本与页面提取"
```

---

### Task 8: 标题解析、收藏链路、站点链路

**Files:**
- Create: `mobile/lib/core/web/html_meta.dart`、`title_resolver.dart`
- Create: `mobile/lib/features/browser/capture_service.dart`、`mobile/lib/features/browser/site_service.dart`
- Modify: `mobile/lib/providers.dart`（`titleResolverProvider`、`captureServiceProvider`、`siteServiceProvider`）
- Test: `mobile/test/core/title_resolver_test.dart`、`mobile/test/features/capture_service_test.dart`

**Interfaces:**
- Consumes: `ApiClient`、`Dio`、`package:html`。
- Produces:
  - `class PageMeta { final String? title; final String? iconUrl; }`
  - `abstract class PageMetaResolver { Future<PageMeta> resolve(String url); }`
  - `class TitleResolver implements PageMetaResolver { TitleResolver(Dio dio); Future<PageMeta> resolve(String url); }`（UA 头、5s 超时、失败返回 `PageMeta(null, null)`，不抛）
  - `String? parseTitle(String html)`、`String? parseIconUrl(String html, Uri pageUrl)`（`html_meta.dart`）
  - `class LinkPreview { final String url; final String title; final String? nearbyImage; final String sourcePage; final bool exists; final String? existingTitle; }`
  - `class CaptureService { CaptureService(ApiClient api, PageMetaResolver resolver); Future<LinkPreview> prepare({required String url, String? linkText, String? nearbyText, String? nearbyImage, required String sourcePage}); Future<void> save(LinkPreview preview, {String? screenshotBase64}); }`
  - `class SiteDraft { final String origin; final String title; final String? iconUrl; final bool exists; final bool inTrash; }`
  - `class SiteService { SiteService(ApiClient api, PageMetaResolver resolver); Future<SiteDraft> prepare(String pageUrl); Future<Site> save(SiteDraft draft); }`

- [ ] **Step 1: 写失败测试**

```dart
test('parseTitle 优先 og:title 再 title', () {
  expect(parseTitle('<title>A</title><meta property="og:title" content="OG">'), 'OG');
  expect(parseTitle('<title>A</title>'), 'A');
});
test('parseIconUrl 把相对 href 转绝对', () {
  expect(parseIconUrl('<link rel="icon" href="/f.ico">', Uri.parse('https://a.com/x')),
    'https://a.com/f.ico');
});
test('prepare 在标题解析失败时回退顺序 linkText → nearbyText → url', () async {
  // fake TitleResolver 返回 null，fake ApiClient.exists=false
  final p = await service.prepare(url: 'https://a.com', linkText: '链接文字', nearbyText: '附近文字', sourcePage: 'https://b.com');
  expect(p.title, '链接文字');
});
test('save 发送 snake_case 与 source_page', () async {
  // fake ApiClient 记录 AddLinkRequest；save 后断言字段
});
test('SiteService.prepare 使用 origin 并返回 inTrash', () async {
  // pageUrl 'https://a.com/x' → origin 'https://a.com'；siteExists → {exists:false,inTrash:true}
});
```

- [ ] **Step 2: 实现并验证**

- `TitleResolver`：`dio.get<String>(url, options: Options(responseType: ResponseType.plain, headers: {'User-Agent': 'Mozilla/5.0 ...', 'Accept': 'text/html'}, receiveTimeout: 5s))`；`parseTitle`：`og:title` 的 `content` 优先，其次 `document.querySelector('title')`。
- `CaptureService.prepare`：并行 `linkExists(url)` 与 `titleResolver.resolve(url)`；`title = meta.title ?? linkText ?? nearbyText ?? url`；`existingTitle = existsResult.link?.title`。
- `CaptureService.save`：`AddLinkRequest(url, title, nearbyImage, screenshotBase64, sourcePage, customData: {'kind': 'link', 'platform': 'android'})` → `api.addLink`。
- `SiteService.prepare`：`originOf(pageUrl)` 为空返回占位 `SiteDraft(origin:'', ...)` 或抛 `ValidationException`；`siteExists(origin)` 与 `resolve(origin)` 并行；title = meta.title ?? host；`iconUrl = meta.iconUrl ?? '$origin/favicon.ico'`。
- `SiteService.save`：`api.addSite(SiteInput(url: draft.origin, title: draft.title, iconUrl: draft.iconUrl))`。

- [ ] **Step 3: 验证并提交**

```bash
flutter test test/core/title_resolver_test.dart test/features/capture_service_test.dart
flutter analyze
git add lib/core/web lib/features/browser lib/providers.dart test
git commit -m "feat(mobile): 标题解析与收藏/站点链路"
```

---

### Task 9: 长按 Sheet、收藏当前页、菜单置顶

**Files:**
- Create: `mobile/lib/features/browser/long_press_sheet.dart`
- Modify: `mobile/lib/features/browser/browser_screen.dart`、`tab_webview.dart`、`browser_toolbar.dart`
- Test: `mobile/test/features/long_press_sheet_test.dart`

**Interfaces:**
- Consumes: `CaptureService`、`SiteService`、`LinkPressPayload`。
- Produces:
  - `LongPressSheet` widget 参数：`url`、`sourcePage`、`linkText`、`nearbyText`、`nearbyImage`、`Future<String?> Function() takeScreenshot`、`onSaved`。
  - 行为：打开即并行加载预览；加载完成显示标题/缩略图/已收藏标记；第一项固定"收藏到稍后再看"（主按钮），第二项"收藏主站"，其后"在新标签打开 / 复制链接 / 分享 / 用系统浏览器打开"。

- [ ] **Step 1: 写 widget 测试**

```dart
testWidgets('菜单第一项是收藏，第二项是收藏主站', (tester) async {
  await tester.pumpWidget(_wrap(LongPressSheet(url: 'https://a.com/x', sourcePage: 'https://b.com',
    linkText: 't', nearbyText: null, nearbyImage: null,
    takeScreenshot: () async => null, onSaved: () {})));
  await tester.pumpAndSettle();
  final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
  expect((tiles[0].title as Text).data, '收藏到稍后再看');
  expect((tiles[1].title as Text).data, '收藏主站');
});
testWidgets('已收藏时收藏按钮禁用并显示“已收藏”', ...);
testWidgets('点击收藏调用 CaptureService.save 并关闭', ...);
testWidgets('服务器未配置时显示“去设置”入口', ...);
testWidgets('保存失败时保留 Sheet 并显示“重试”', ...);
```

- [ ] **Step 2: 实现并接线**

- `TabWebView.onLongPressLink` → `showModalBottomSheet(isScrollControlled: true, builder: (_) => LongPressSheet(..., takeScreenshot: () async { final bytes = await controller.takeScreenshot(); return base64Encode(bytes!); }))`。
- `BrowserToolbar.onCollectPage`：用当前 URL + 当前标题调 `CaptureService.prepare`，直接 `save`（截图同法），成功后 SnackBar。
- 复制链接用 `Clipboard.setData`；分享用 `Share.share(url)`；系统浏览器用 `url_launcher`。
- 收藏主站：`SiteService.prepare(originOf(pageUrl))` → `save`；已存在/回收站恢复由服务端处理，成功后 SnackBar 提示"已收藏站点"或"已恢复站点"。
- 图片/截图总量 > 8MB 时按 Global Constraints 丢弃并提示。

- [ ] **Step 3: 验证并提交**

```bash
flutter test test/features/long_press_sheet_test.dart
flutter analyze
git add lib test
git commit -m "feat(mobile): 长按收藏菜单与收藏当前页"
```

---

### Task 10: M0 真机验证

**Files:**
- Create: `docs/superpowers/plans/m0-verification.md`（记录结果）

- [ ] **Step 1: 在平板真机跑通以下 6 项并记录**

1. 2 个标签切换不白屏、返回不丢状态（`IndexedStack + Offstage` 有效）。
2. B 站/YouTube 点全屏可横屏播放，退出后工具栏与系统栏恢复。
3. 真实站点长按链接稳定弹菜单；滚动后不弹；菜单关闭不误跳转。
4. `takeScreenshot` 截图内容正确（非黑屏/非空）。
5. 收藏链路打到真实服务器：`POST /api/links` 成功、列表可见、图片落盘。
6. `onCreateWindow`（新标签）、`onDownloadStartRequest`（提示）行为符合预期。

- [ ] **Step 2: 记录与提交**

每项写"通过/不通过 + 现象 + 设备型号"。任一项不通过：停止后续任务，回到 spec 调整方案后在计划中追加修复任务。

```bash
git add docs/superpowers/plans/m0-verification.md
git commit -m "docs(mobile): M0 真机验证记录"
```

---

### Task 11: 收藏库

**Files:**
- Create: `mobile/lib/features/library/library_notifier.dart`、`link_card.dart`
- Modify: `mobile/lib/features/library/library_screen.dart`（替换占位）
- Modify: `mobile/lib/providers.dart`（`libraryProvider`）
- Test: `mobile/test/features/library_notifier_test.dart`、`mobile/test/features/library_screen_test.dart`

**Interfaces:**
- Consumes: `ApiClient`、`BrowserNotifier`。
- Produces:
  - `class LibraryState { List<LinkItem> links; int total; int page; bool loading; String? error; String search; String sortBy; bool sortDesc; bool hasMore; }`
  - `class LibraryNotifier extends Notifier<LibraryState>`：`Future<void> refresh()`、`Future<void> loadMore()`、`void setSearch(String)`（300ms 防抖后 refresh）、`void setSort({String? sortBy, bool? sortDesc})`、`Future<void> deleteLink(String id)`（乐观更新 + 失败回滚）。
  - `LinkCard` widget：缩略图（`cached_network_image`，失败回退 screenshot/占位）、标题、域名、时间。

- [ ] **Step 1: 写失败测试**

```dart
test('loadMore 追加下一页并按 id 去重', () async { ... expect(state.links.length, 2); ... });
test('refresh 重置 page=1 并替换列表', () async { ... });
test('deleteLink 立即从列表移除，失败时回滚', () async { ... });
testWidgets('空列表显示空态文案', ...);
```

- [ ] **Step 2: 实现并验证**

`LibraryNotifier.build()` 返回初始 state 并触发 `refresh()`？Riverpod 里用 `AsyncNotifier` 更自然，但为简化用 `Notifier` + 显式 `init()` 由页面 `initState` 调用。页面：搜索框、排序菜单（时间/标题）、网格/列表切换、`NotificationListener<ScrollNotification>` 触底 `loadMore`、`RefreshIndicator`、删除确认。

- [ ] **Step 3: 提交**

```bash
flutter test test/features/library_notifier_test.dart test/features/library_screen_test.dart
flutter analyze
git add lib test
git commit -m "feat(mobile): 收藏库列表与搜索"
```

---

### Task 12: 回收站（链接 + 站点）

**Files:**
- Create: `mobile/lib/features/library/trash_notifier.dart`
- Modify: `mobile/lib/features/library/trash_screen.dart`（新建，若 Task 4 未建）
- Modify: `mobile/lib/providers.dart`（`trashProvider`）
- Test: `mobile/test/features/trash_notifier_test.dart`

**Interfaces:**
- Consumes: `ApiClient`。
- Produces:
  - `class TrashState { List<TrashItem> links; List<Site> sites; bool loading; String? error; }`
  - `class TrashNotifier extends Notifier<TrashState>`：`load()`、`restoreLink(id)`、`purgeLink(id)`、`restoreSite(id)`、`purgeSite(id)`。
  - 页面：`TabBar` 两个 tab（链接/站点），各自列表 + 还原/永久删除（二次确认）。

- [ ] **Step 1: 写失败测试**

```dart
test('load 同时拉取链接与站点回收站', () async { ... expect(state.links.length, 1); expect(state.sites.length, 1); });
test('restoreSite 调用 api.restoreSite 并从列表移除', () async { ... });
testWidgets('回收站有两个 tab', ...);
```

- [ ] **Step 2: 实现并验证并提交**

```bash
flutter test test/features/trash_notifier_test.dart
flutter analyze
git add lib test
git commit -m "feat(mobile): 回收站（链接与站点）"
```

---

### Task 13: 站点页

**Files:**
- Create: `mobile/lib/features/sites/sites_notifier.dart`、`site_card.dart`
- Modify: `mobile/lib/features/sites/sites_screen.dart`（替换占位）
- Modify: `mobile/lib/providers.dart`（`sitesProvider`）
- Test: `mobile/test/features/sites_notifier_test.dart`

**Interfaces:**
- Consumes: `ApiClient`、`BrowserNotifier`、`SiteService`。
- Produces:
  - `class SitesState { List<Site> sites; bool loading; String? error; }`
  - `class SitesNotifier extends Notifier<SitesState>`：`Future<void> refresh()`、`Future<void> deleteSite(String id)`（软删除，乐观更新）、`Future<Site> addSite(SiteDraft draft)`。
  - `SiteCard`：图标 56dp（`icon_url` → `origin/favicon.ico` → 首字母占位）、名称、host；点按打开浏览器新标签；长按删除确认。

- [ ] **Step 1: 写失败测试**

```dart
test('refresh 加载站点', () async { ... });
test('deleteSite 乐观移除，失败回滚', () async { ... });
testWidgets('站点页空态显示引导文案', ...);
```

- [ ] **Step 2: 实现并验证并提交**

```bash
flutter test test/features/sites_notifier_test.dart
flutter analyze
git add lib test
git commit -m "feat(mobile): 站点收藏页"
```

---

### Task 14: 设置页

**Files:**
- Modify: `mobile/lib/features/settings/settings_screen.dart`（替换占位）
- Create: `mobile/lib/features/settings/theme_controller.dart`
- Modify: `mobile/lib/app.dart`（watch `themeProvider` 设置 `MaterialApp.router.themeMode`）
- Modify: `mobile/lib/providers.dart`（`themeProvider`）
- Test: `mobile/test/features/settings_screen_test.dart`

**Interfaces:**
- Consumes: `ConfigStore`、`ApiClient`。
- Produces:
  - `ThemeController extends Notifier<ThemeMode>`：`setMode(ThemeMode)`，持久化到 `SharedPreferences`（key `theme_mode`）。
  - 设置页：服务器地址 + API Key + 保存并测试连接、连接状态、主题选择、清除浏览数据（`CookieManager.deleteAllCookies()` + `InAppWebViewController.clearAllCache()` / `WebStorageManager`）、"从平板浏览器导入标签页"说明弹窗（只展示 adb 命令，不执行）、版本号。

- [ ] **Step 1: 写 widget 测试**

```dart
testWidgets('空 URL 保存时提示错误', ...);
testWidgets('保存调用 ConfigStore.save 并显示成功', ...);
testWidgets('测试连接失败显示错误 SnackBar', ...);
```

- [ ] **Step 2: 实现并验证并提交**

```bash
flutter test test/features/settings_screen_test.dart
flutter analyze
git add lib test
git commit -m "feat(mobile): 设置页与服务器配置"
```

---

### Task 15: Android 平台配置、构建与验收

**Files:**
- Modify: `mobile/android/app/src/main/AndroidManifest.xml`
- Modify: `mobile/android/app/build.gradle.kts`
- Modify: `AGENTS.md`（移动端章节）、`CHANGELOG.md`（Unreleased → Mobile Added）

**Interfaces:**
- Consumes: 全部功能。
- Produces: 可侧载的 release APK；文档。

- [ ] **Step 1: Manifest 与 Gradle**

- `<uses-permission android:name="android.permission.INTERNET"/>`、`ACCESS_NETWORK_STATE`。
- `<application android:label="稍后再看" android:usesCleartextTraffic="true">`（个人自用允许内网 http；设置页提示公网请用 HTTPS）。
- `MainActivity` 加 `android:configChanges="orientation|screenSize|smallestScreenSize|keyboardHidden"`。
- `build.gradle.kts`：`minSdk = 26`、`targetSdk = flutter.targetSdkVersion`、`applicationId = "com.cpf23333.readlater"`。

- [ ] **Step 2: 构建与安装**

```bash
cd mobile
flutter analyze
flutter test
flutter build apk --release --split-per-abi
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Expected: 构建成功；安装后能启动、连接服务器、完成一次长按收藏。

- [ ] **Step 3: 全量验收（对照 spec 11/13.1）**

在平板真机勾选：多标签、视频全屏、长按菜单置顶、截图、去重、列表搜索/删除、回收站（链接+站点）、站点收藏/删除/还原、设置连接、深色模式、横竖屏。任何一项失败记录后回补修复任务。

- [ ] **Step 4: 文档与提交**

`AGENTS.md` 增加 `mobile/` 章节（技术栈、构建/测试命令、目录结构）；`CHANGELOG.md` 的 `[Unreleased]` 下加 `### Mobile` → `#### Added`（功能清单 + 平台配置）。

```bash
git add mobile AGENTS.md CHANGELOG.md
git commit -m "feat(mobile): Android 平台配置、构建与验收"
```
