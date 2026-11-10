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

Widget wrapSheet(
  FakeApiClient api, {
  FakePageMetaResolver? resolver,
  String url = 'https://a.com/x',
  ValueChanged<String>? onOpenInBackground,
}) {
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
          onOpenInBackground: onOpenInBackground,
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

  testWidgets('打开菜单不解析标题/图片，点击收藏时才解析', (tester) async {
    final resolver = FakePageMetaResolver();
    final api = FakeApiClient();
    await tester.pumpWidget(wrapSheet(api, resolver: resolver));
    await tester.pumpAndSettle();

    expect(resolver.resolveCalls, 0);

    await tester.tap(find.text('收藏到稍后再看'));
    await tester.pumpAndSettle();

    expect(resolver.resolveCalls, 1);
    expect(api.addedLinks.length, 1);
  });

  testWidgets('已收藏也始终显示收藏，点击调用 addLink', (tester) async {
    final api = FakeApiClient(
      linkExistsResult: const ExistsResult(
        exists: true,
        link: LinkItem(
          id: '1',
          url: 'https://a.com/x',
          title: '旧',
          createdAt: 1,
        ),
      ),
    );
    await tester.pumpWidget(wrapSheet(api));
    await tester.pumpAndSettle();

    expect(find.text('收藏到稍后再看'), findsOneWidget);
    expect(api.linkExistsCalls, 0);

    await tester.tap(find.text('收藏到稍后再看'));
    await tester.pumpAndSettle();

    expect(api.addedLinks.length, 1);
  });

  testWidgets('后台打开新标签页会回调 URL', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(
      wrapSheet(FakeApiClient(), onOpenInBackground: opened.add),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('后台打开新标签页'));
    await tester.pumpAndSettle();

    expect(opened, ['https://a.com/x']);
  });

  testWidgets('保存时解析失败显示错误提示', (tester) async {
    final resolver = FakePageMetaResolver(error: const NetworkException());
    await tester.pumpWidget(wrapSheet(FakeApiClient(), resolver: resolver));
    await tester.pumpAndSettle();

    await tester.tap(find.text('收藏到稍后再看'));
    await tester.pumpAndSettle();

    expect(find.textContaining('保存失败'), findsOneWidget);
  });
}
