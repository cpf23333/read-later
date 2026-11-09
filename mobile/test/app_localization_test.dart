import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('中文环境下 Material 框架文案为中文（文本选择工具栏等）', (tester) async {
    MaterialLocalizations? localizations;

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (context) {
          localizations = MaterialLocalizations.of(context);
          return const Scaffold(body: SizedBox());
        },
      ),
    ));
    await tester.pumpAndSettle();

    expect(localizations, isNotNull);
    expect(localizations!.copyButtonLabel, '复制');
    expect(localizations!.selectAllButtonLabel, '全选');
    expect(localizations!.cutButtonLabel, '剪切');
  });

  testWidgets('未配置 zh 时框架文案回退英文（回归防护）', (tester) async {
    MaterialLocalizations? localizations;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) {
          localizations = MaterialLocalizations.of(context);
          return const Scaffold(body: SizedBox());
        },
      ),
    ));
    await tester.pumpAndSettle();

    expect(localizations!.copyButtonLabel, 'Copy');
  });
}
