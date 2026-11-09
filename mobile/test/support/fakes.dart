import 'package:readlater/core/config/key_value_store.dart';
import 'package:readlater/core/config/config_store.dart';

/// 内存键值存储（测试用）。
class InMemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

/// 用内存存储预置服务器配置（测试用）。
ConfigStore fakeConfigStore({required String baseUrl, required String apiKey}) {
  final store = InMemoryKeyValueStore();
  store.values[ConfigStore.storageKey] =
      '{"baseUrl":"$baseUrl","apiKey":"$apiKey","enabled":true}';
  return ConfigStore(store);
}
