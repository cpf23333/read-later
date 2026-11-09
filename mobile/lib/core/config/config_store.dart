import 'dart:convert';

import '../models/config.dart';
import 'key_value_store.dart';

/// 服务器配置存储（JSON 序列化后写入 KeyValueStore）。
class ConfigStore {
  ConfigStore(this._store);

  static const storageKey = 'server_config';

  final KeyValueStore _store;

  Future<ServerConfig> read() async {
    final raw = await _store.read(storageKey);
    if (raw == null || raw.isEmpty) return const ServerConfig();

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return ServerConfig.fromJson(decoded);
      }
    } catch (_) {
      // 损坏的配置回退为默认值，避免启动崩溃。
    }
    return const ServerConfig();
  }

  Future<void> save(ServerConfig config) async {
    final normalized = config.copyWith(baseUrl: _normalizeBaseUrl(config.baseUrl));
    await _store.write(storageKey, jsonEncode(normalized.toJson()));
  }

  Future<bool> isConfigured() async => (await read()).isConfigured;

  String _normalizeBaseUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  }
}
