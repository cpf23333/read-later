import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/features/library/trash_screen.dart';
import 'package:readlater/providers.dart';

import '../support/fakes.dart';

void main() {
  testWidgets('回收站有链接与站点两个 tab', (tester) async {
    final api = FakeApiClient();

    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: const MaterialApp(home: TrashScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('链接'), findsOneWidget);
    expect(find.text('站点'), findsOneWidget);
    expect(find.text('链接回收站是空的'), findsOneWidget);
  });
}
