import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/models/domain_stat.dart';
import 'package:readlater/core/models/link.dart';
import 'package:readlater/core/models/site.dart';
import 'package:readlater/features/browser/new_tab_page.dart';
import 'package:readlater/providers.dart';

import '../support/fakes.dart';

void main() {
  testWidgets('新标签页显示常用站点与最近收藏', (tester) async {
    final api = FakeApiClient(
      sites: [
        const Site(
          id: 's1',
          url: 'https://example.com',
          title: 'Example',
          createdAt: 1,
        ),
      ],
      links: [
        const LinkItem(
          id: 'l1',
          url: 'https://example.com/a',
          title: '文章 A',
          createdAt: 1,
        ),
      ],
      domains: const [DomainStat(domain: 'example.com', count: 3)],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: MaterialApp(
          home: Scaffold(body: NewTabPage(onNavigate: (_) {})),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('常用站点'), findsOneWidget);
    expect(find.text('Example'), findsOneWidget);
    expect(find.text('最近收藏'), findsOneWidget);
    expect(find.text('文章 A'), findsOneWidget);
    expect(find.text('example.com (3)'), findsOneWidget);
  });

  testWidgets('提交输入时规范化并回调 URL', (tester) async {
    final navigated = <String>[];
    final api = FakeApiClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: MaterialApp(
          home: Scaffold(body: NewTabPage(onNavigate: navigated.add)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'example.com');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();

    expect(navigated, ['https://example.com']);
  });
}
