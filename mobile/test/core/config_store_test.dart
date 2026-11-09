import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/config/config_store.dart';
import 'package:readlater/core/models/config.dart';

import '../support/fakes.dart';

void main() {
  test('未保存时返回禁用配置', () async {
    final store = ConfigStore(InMemoryKeyValueStore());
    final cfg = await store.read();
    expect(cfg.enabled, isFalse);
    expect(cfg.baseUrl, isEmpty);
    expect(await store.isConfigured(), isFalse);
  });

  test('保存时去掉 baseUrl 末尾斜杠并可读回', () async {
    final store = ConfigStore(InMemoryKeyValueStore());
    await store.save(
      const ServerConfig(baseUrl: 'http://192.168.1.2:3000/', apiKey: 'k', enabled: true),
    );
    final cfg = await store.read();
    expect(cfg.baseUrl, 'http://192.168.1.2:3000');
    expect(cfg.apiKey, 'k');
    expect(await store.isConfigured(), isTrue);
  });

  test('损坏的配置回退为默认值', () async {
    final backing = InMemoryKeyValueStore();
    backing.values[ConfigStore.storageKey] = 'not-json';
    final cfg = await ConfigStore(backing).read();
    expect(cfg.enabled, isFalse);
  });
}
