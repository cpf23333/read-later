import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/app.dart';

void main() {
  testWidgets('渲染 4 个导航目的地，默认在收藏库', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ReadLaterApp()));
    await tester.pumpAndSettle();

    for (final label in ['收藏', '站点', '浏览器', '设置']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('收藏库占位'), findsOneWidget);
  });

  testWidgets('点击站点切换到站点占位页', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ReadLaterApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('站点').first);
    await tester.pumpAndSettle();

    expect(find.text('站点占位'), findsOneWidget);
  });
}
