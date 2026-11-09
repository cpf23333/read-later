import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('InAppWebView.takeScreenshot 返回非空字节', (tester) async {
    late InAppWebViewController controller;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: InAppWebView(
          initialFile: 'assets/test/fixture.html',
          initialSettings: InAppWebViewSettings(javaScriptEnabled: true),
          onWebViewCreated: (created) => controller = created,
        ),
      ),
    ));

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    final bytes = await controller.takeScreenshot();

    expect(bytes, isNotNull);
    expect(bytes!.length, greaterThan(0));
  });
}
