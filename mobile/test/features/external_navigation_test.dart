import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/features/browser/external_navigation.dart';

void main() {
  group('classifyNavigation', () {
    test('http(s)/about/data/blob 属内部导航', () {
      for (final scheme in ['http', 'https', 'about', 'data', 'blob']) {
        expect(
          classifyNavigation(scheme: scheme, hasGesture: false),
          ExternalNavigationKind.internal,
          reason: scheme,
        );
      }
    });

    test('外部 scheme + 用户手势 → 需要确认', () {
      expect(
        classifyNavigation(scheme: 'taobao', hasGesture: true),
        ExternalNavigationKind.externalUserGesture,
      );
      expect(
        classifyNavigation(scheme: 'intent', hasGesture: true),
        ExternalNavigationKind.externalUserGesture,
      );
    });

    test('外部 scheme 无手势（脚本/重定向）→ 自动拦截', () {
      expect(
        classifyNavigation(scheme: 'weixin', hasGesture: false),
        ExternalNavigationKind.externalAutomatic,
      );
    });

    test('大小写与空 scheme', () {
      expect(isExternalScheme('Taobao'), isTrue);
      expect(isExternalScheme('HTTP'), isFalse);
      expect(isExternalScheme(null), isFalse);
      expect(isExternalScheme(''), isFalse);
    });
  });

  testWidgets('确认弹窗：取消返回 false，打开返回 true', (tester) async {
    late Future<bool> result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () {
              result = confirmExternalLaunch(
                context,
                url: 'taobao://item/1',
                scheme: 'taobao',
              );
            },
            child: const Text('触发'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('触发'));
    await tester.pumpAndSettle();
    expect(find.text('打开外部应用？'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);

    await tester.tap(find.text('触发'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });
}
