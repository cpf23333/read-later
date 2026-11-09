import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/api/errors.dart';
import 'package:readlater/core/models/link.dart';
import 'package:readlater/features/browser/capture_service.dart';
import 'package:readlater/features/browser/long_press_sheet.dart';
import 'package:readlater/features/browser/site_service.dart';
import 'package:readlater/providers.dart';

import '../support/fakes.dart';

Widget wrapSheet(FakeApiClient api, {FakePageMetaResolver? resolver, String url = 'https://a.com/x'}) {
  final meta = resolver ?? FakePageMetaResolver();
  return ProviderScope(
    overrides: [
      captureServiceProvider.overrideWithValue(CaptureService(api, meta)),
      siteServiceProvider.overrideWithValue(SiteService(api, meta)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: LongPressSheet(
          url: url,
          sourcePage: 'https://b.com',
          linkText: '链接文字',
          takeScreenshot: () async => null,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('菜单第一项是收藏，第二项是收藏主站', (tester) async {
    await tester.pumpWidget(wrapSheet(FakeApiClient()));
    await tester.pumpAndSettle();

    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect(tiles.length, greaterThanOrEqualTo(2));
    expect((tiles[0].title as Text).data, '收藏到稍后再看');
    expect((tiles[1].title as Text).data, '收藏主站 a.com');
  });

  testWidgets('已收藏也始终显示收藏，点击调用 addLink', (tester) async {
    final api = FakeApiClient(
      linkExistsResult: const ExistsResult(
        exists: true,
        link: LinkItem(id: '1', url: 'https://a.com/x', title: '旧', createdAt: 1),
      ),
    );
    await tester.pumpWidget(wrapSheet(api));
    await tester.pumpAndSettle();

    expect(find.text('收藏到稍后再看'), findsOneWidget);
    expect(find.text('更新收藏信息'), findsNothing);
    expect(api.linkExistsCalls, 0);

    await tester.tap(find.text('收藏到稍后再看'));
    await tester.pumpAndSettle();

    expect(api.addedLinks.length, 1);
  });

  testWidgets('点击收藏会调用 Save（发送 addLink）', (tester) async {
    final api = FakeApiClient();
    await tester.pumpWidget(wrapSheet(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('收藏到稍后再看'));
    await tester.pumpAndSettle();

    expect(api.addedLinks.length, 1);
  });

  testWidgets('加载失败时显示重试，重试后恢复', (tester) async {
    final resolver = FakePageMetaResolver(error: const NetworkException());
    await tester.pumpWidget(wrapSheet(FakeApiClient(), resolver: resolver));
    await tester.pumpAndSettle();

    expect(find.textContaining('加载失败'), findsOneWidget);

    resolver.error = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.textContaining('加载失败'), findsNothing);
  });

  testWidgets('服务器未配置时显示去设置入口', (tester) async {
    final resolver = FakePageMetaResolver(error: const NotConfiguredException());
    await tester.pumpWidget(wrapSheet(FakeApiClient(), resolver: resolver));
    await tester.pumpAndSettle();

    expect(find.text('服务器未配置，去设置'), findsOneWidget);
  });
}
