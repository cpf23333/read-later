import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/models/site.dart';
import 'package:readlater/features/sites/sites_screen.dart';
import 'package:readlater/providers.dart';

import '../support/fakes.dart';

void main() {
  testWidgets('站点为空时显示引导文案', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(FakeApiClient())],
      child: const MaterialApp(home: SitesScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('收藏主站'), findsOneWidget);
  });

  testWidgets('渲染站点卡片名称', (tester) async {
    final api = FakeApiClient(
      sites: [const Site(id: 's1', url: 'https://a.com', title: '站点名', createdAt: 1)],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: const MaterialApp(home: SitesScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('站点名'), findsOneWidget);
    expect(find.text('a.com'), findsOneWidget);
  });
}
