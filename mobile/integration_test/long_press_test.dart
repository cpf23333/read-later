import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:readlater/features/browser/inject_loader.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('fixture 页面：长按钩子回调 URL，提取结果通过 handler 回传', (tester) async {
    final payloads = <Map>[];
    final extractCompleter = Completer<Map<String, dynamic>>();
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
            created.addJavaScriptHandler(
              handlerName: 'rl:extractResult',
              callback: (args) {
                final raw = args.first as String;
                if (!extractCompleter.isCompleted) {
                  extractCompleter.complete(jsonDecode(raw) as Map<String, dynamic>);
                }
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

    await controller.evaluateJavascript(
      source: "window.__rlExtract('https://example.com/article')",
    );
    final data = await extractCompleter.future.timeout(const Duration(seconds: 5));

    expect(data['linkText'], '文章');
    expect(data['nearbyImage'], isNotNull);
  });
}
