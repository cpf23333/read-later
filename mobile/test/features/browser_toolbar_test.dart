import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/features/browser/browser_toolbar.dart';

void main() {
  testWidgets('地址栏显示当前 URL，提交触发 onNavigate', (tester) async {
    String? navigated;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BrowserToolbar(
          url: 'https://a.com',
          canGoBack: false,
          canGoForward: false,
          loading: false,
          onNavigate: (value) => navigated = value,
          onBack: () {},
          onForward: () {},
          onReload: () {},
          onStop: () {},
          onCollectPage: () {},
          onMenu: () {},
        ),
      ),
    ));

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'https://a.com',
    );

    await tester.enterText(find.byType(TextField), 'example.com');
    await tester.testTextInput.receiveAction(TextInputAction.go);

    expect(navigated, 'https://example.com');
  });

  test('normalizeUserInput 补全 scheme 与搜索', () {
    expect(normalizeUserInput('example.com'), 'https://example.com');
    expect(normalizeUserInput(''), '');
    expect(
      normalizeUserInput('flutter webview'),
      'https://www.bing.com/search?q=flutter%20webview',
    );
  });
}
