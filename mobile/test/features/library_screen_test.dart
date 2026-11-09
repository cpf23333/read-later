import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/models/domain_stat.dart';
import 'package:readlater/core/models/link.dart';
import 'package:readlater/features/library/link_card.dart';
import 'package:readlater/features/library/library_screen.dart';
import 'package:readlater/providers.dart';

import '../support/fakes.dart';

Widget wrap(FakeApiClient api) {
  return ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api)],
    child: const MaterialApp(home: LibraryScreen()),
  );
}

void main() {
  testWidgets('空列表显示空态文案', (tester) async {
    await tester.pumpWidget(wrap(FakeApiClient()));
    await tester.pumpAndSettle();

    expect(find.text('还没有收藏，去浏览器长按链接试试'), findsOneWidget);
  });

  testWidgets('渲染收藏卡片标题与域名', (tester) async {
    final api = FakeApiClient(
      links: [
        const LinkItem(
          id: '1',
          url: 'https://example.com/a',
          title: '示例文章',
          createdAt: 1,
        ),
      ],
      total: 1,
    );

    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();

    expect(find.text('示例文章'), findsOneWidget);
    expect(find.text('example.com'), findsOneWidget);
  });

  testWidgets('无标题卡片显示完整 URL', (tester) async {
    final api = FakeApiClient(
      links: [
        const LinkItem(
          id: '1',
          url: 'https://example.com/path/to/article',
          title: '',
          createdAt: 1,
        ),
      ],
      total: 1,
    );

    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();

    expect(find.text('https://example.com/path/to/article'), findsOneWidget);
  });

  testWidgets('按域名筛选', (tester) async {
    final api = FakeApiClient(
      links: [
        const LinkItem(
          id: '1',
          url: 'https://example.com/a',
          title: '示例',
          createdAt: 1,
        ),
      ],
      total: 1,
      domains: const [DomainStat(domain: 'example.com', count: 2)],
    );

    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('按域名筛选'));
    await tester.pumpAndSettle();
    expect(find.text('example.com'), findsWidgets);

    await tester.tap(find.text('example.com').last);
    await tester.pumpAndSettle();

    expect(api.listLinksDomains.last, 'example.com');
    expect(find.byType(InputChip), findsOneWidget);
  });

  testWidgets('长按卡片进入多选模式', (tester) async {
    final api = FakeApiClient(
      links: [
        const LinkItem(id: '1', url: 'https://example.com/a', title: '示例', createdAt: 1),
      ],
      total: 1,
    );

    await tester.pumpWidget(wrap(api));
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(LinkCard));
    await tester.pumpAndSettle();

    expect(find.text('已选 1'), findsOneWidget);
  });
}
