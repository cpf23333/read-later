import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/app.dart';
import 'package:readlater/core/config/config_store.dart';
import 'package:readlater/features/library/library_screen.dart';
import 'package:readlater/features/sites/sites_screen.dart';
import 'package:readlater/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget app() {
    return ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(FakeApiClient()),
        configStoreProvider.overrideWithValue(ConfigStore(InMemoryKeyValueStore())),
      ],
      child: const ReadLaterApp(),
    );
  }

  testWidgets('渲染 4 个导航目的地，默认在收藏库', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    for (final label in ['收藏', '站点', '浏览器', '设置']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.byType(LibraryScreen), findsOneWidget);
  });

  testWidgets('点击站点切换到站点页', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('站点').first);
    await tester.pumpAndSettle();

    expect(find.byType(SitesScreen), findsOneWidget);
  });
}
