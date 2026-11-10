import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
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
import 'features/browser/global_user_agent.dart';
import 'features/browser/site_service.dart';
import 'features/browser/tab_registry.dart';
import 'features/library/library_notifier.dart';
import 'features/library/trash_notifier.dart';
import 'features/settings/theme_controller.dart';
import 'features/settings/video_settings_controller.dart';
import 'features/sites/sites_notifier.dart';

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
    ref.watch(captureServiceProvider),
  ),
);

/// 收藏库列表状态。
final libraryProvider = NotifierProvider<LibraryNotifier, LibraryState>(
  LibraryNotifier.new,
);

/// 回收站状态。
final trashProvider = NotifierProvider<TrashNotifier, TrashState>(
  TrashNotifier.new,
);

/// 站点页状态。
final sitesProvider = NotifierProvider<SitesNotifier, SitesState>(
  SitesNotifier.new,
);

/// 全局默认 User-Agent。
final globalUserAgentProvider =
    NotifierProvider<GlobalUserAgentController, GlobalUserAgentState>(
  GlobalUserAgentController.new,
);

/// 主题模式。
final themeProvider = NotifierProvider<ThemeController, ThemeMode>(
  ThemeController.new,
);

/// 视频播放偏好（自动播放、是否显示播放按钮）。
final videoSettingsProvider =
    NotifierProvider<VideoSettingsController, VideoSettings>(
  VideoSettingsController.new,
);
