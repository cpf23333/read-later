import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:readlater/features/browser/inject_loader.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('fixture 页面：长按钩子回调 URL，提取返回 JSON', (tester) async {
    final payloads = <Map>[];
    final injectJs = await loadInjectJs(rootBundle);

    late InAppWebViewController controller;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: InAppWebView(
          initialFile: 'assets/test/fixture.html',
          initialSettings: InAppWebViewSettings(javaScriptEnabled: true),
          initialUserScripts: UnmodifiableListView<UserScript>([
            UserScript(
              source: injectJs,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              forMainFrameOnly: true,
            ),
          ]),
          onWebViewCreated: (created) {
            controller = created;
            created.addJavaScriptHandler(
              handlerName: 'rl:longPress',
              callback: (args) {
                payloads.add(args.first as Map);
                return null;
              },
            );
          },
        ),
      ),
    ));

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    await controller.evaluateJavascript(source: "window.__rlTestLongPress('#link')");
    await tester.pumpAndSettle();

    expect(payloads, isNotEmpty);
    expect(payloads.single['url'], 'https://example.com/article');

    final extracted = await controller.evaluateJavascript(
      source: "window.__rlExtract('https://example.com/article')",
    );
    final json = extracted as String;
    expect(json, contains('文章'));
    expect(json, contains('nearbyImage'));
  });
}
