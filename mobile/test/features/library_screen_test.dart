import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/models/link.dart';
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
}
