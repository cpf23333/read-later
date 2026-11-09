import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/api/errors.dart';
import 'package:readlater/core/config/config_store.dart';
import 'package:readlater/features/settings/settings_screen.dart';
import 'package:readlater/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

Widget wrap({required FakeApiClient api, required ConfigStore configStore}) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      configStoreProvider.overrideWithValue(configStore),
    ],
    child: const MaterialApp(home: SettingsScreen()),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('空服务器地址时提示错误', (tester) async {
    final configStore = ConfigStore(InMemoryKeyValueStore());
    await tester.pumpWidget(wrap(api: FakeApiClient(), configStore: configStore));
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存并测试连接'));
    await tester.pump();

    expect(find.text('请填写服务器地址'), findsOneWidget);
  });

  testWidgets('保存配置并显示连接成功', (tester) async {
    final configStore = ConfigStore(InMemoryKeyValueStore());
    await tester.pumpWidget(wrap(api: FakeApiClient(), configStore: configStore));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, '服务器地址'),
      'http://192.168.1.2:3000',
    );
    await tester.enterText(find.widgetWithText(TextField, 'API Key'), 'test-key');
    await tester.tap(find.text('保存并测试连接'));
    await tester.pump(const Duration(milliseconds: 300));

    final saved = await configStore.read();
    expect(saved.baseUrl, 'http://192.168.1.2:3000');
    expect(saved.apiKey, 'test-key');
    expect(saved.enabled, isTrue);
    expect(find.text('已保存，连接成功'), findsOneWidget);
  });

  testWidgets('测试连接失败时提示失败', (tester) async {
    final configStore = ConfigStore(InMemoryKeyValueStore());
    final api = FakeApiClient(error: const NetworkException());
    await tester.pumpWidget(wrap(api: api, configStore: configStore));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, '服务器地址'),
      'http://192.168.1.2:3000',
    );
    await tester.enterText(find.widgetWithText(TextField, 'API Key'), 'k');
    await tester.tap(find.text('保存并测试连接'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('连接失败'), findsWidgets);
  });
}
