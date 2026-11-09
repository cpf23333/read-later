import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/api/api_client.dart';
import 'core/api/dio_api_client.dart';
import 'core/config/config_store.dart';
import 'core/config/key_value_store.dart';

/// 服务器配置存储。
final configStoreProvider = Provider<ConfigStore>(
  (ref) => ConfigStore(SecureKeyValueStore()),
);

/// 服务器 API 客户端。
final apiClientProvider = Provider<ApiClient>(
  (ref) => DioApiClient(Dio(), ref.watch(configStoreProvider)),
);
