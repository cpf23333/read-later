import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/api/api_client.dart';
import 'core/api/dio_api_client.dart';
import 'core/config/config_store.dart';
import 'core/config/key_value_store.dart';
import 'core/storage/session_store.dart';
import 'core/web/title_resolver.dart';
import 'features/browser/browser_notifier.dart';
import 'features/browser/browser_state.dart';
import 'features/browser/capture_service.dart';
import 'features/browser/site_service.dart';
import 'features/browser/tab_registry.dart';
import 'features/library/library_notifier.dart';

/// 服务器配置存储。
final configStoreProvider = Provider<ConfigStore>(
  (ref) => ConfigStore(SecureKeyValueStore()),
);

/// 服务器 API 客户端。
final apiClientProvider = Provider<ApiClient>(
  (ref) => DioApiClient(Dio(), ref.watch(configStoreProvider)),
);

/// 浏览器会话持久化。
final sessionStoreProvider = Provider<SessionStore>(
  (ref) => SharedPreferencesSessionStore(),
);

/// 标签控制器注册表。
final tabRegistryProvider = Provider<TabRegistry>((ref) => TabRegistry());

/// 多标签状态。
final browserProvider = NotifierProvider<BrowserNotifier, BrowserState>(
  BrowserNotifier.new,
);

/// 目标页标题/favicon 解析。
final titleResolverProvider = Provider<PageMetaResolver>(
  (ref) => TitleResolver(Dio()),
);

/// 收藏链接链路。
final captureServiceProvider = Provider<CaptureService>(
  (ref) => CaptureService(
    ref.watch(apiClientProvider),
    ref.watch(titleResolverProvider),
  ),
);

/// 收藏主站链路。
final siteServiceProvider = Provider<SiteService>(
  (ref) => SiteService(
    ref.watch(apiClientProvider),
    ref.watch(titleResolverProvider),
  ),
);

/// 收藏库列表状态。
final libraryProvider = NotifierProvider<LibraryNotifier, LibraryState>(
  LibraryNotifier.new,
);
