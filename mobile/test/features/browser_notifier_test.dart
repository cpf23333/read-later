import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/features/browser/browser_notifier.dart';
import 'package:readlater/providers.dart';

import '../support/fakes.dart';

ProviderContainer makeContainer(InMemorySessionStore store) {
  return ProviderContainer(
    overrides: [sessionStoreProvider.overrideWithValue(store)],
  );
}

void main() {
  test('openTab 激活新标签并保留旧标签', () {
    final store = InMemorySessionStore();
    final container = makeContainer(store);
    addTearDown(container.dispose);

    final notifier = container.read(browserProvider.notifier);
    notifier.openTab('https://a.com');
    notifier.openTab('https://b.com');

    expect(notifier.state.tabs.length, 3); // 初始空白 + 两个
    expect(notifier.state.activeTab?.url, 'https://b.com');
  });

  test('超过 10 个标签时关闭最久未使用的非活动标签', () {
    final store = InMemorySessionStore();
    final container = makeContainer(store);
    addTearDown(container.dispose);

    final notifier = container.read(browserProvider.notifier);
    for (var i = 0; i < 12; i++) {
      notifier.openTab('https://example.com/$i');
    }

    expect(notifier.state.tabs.length, BrowserNotifier.maxTabs);
  });

  test('关闭最后一个标签后保留 about:blank', () {
    final store = InMemorySessionStore();
    final container = makeContainer(store);
    addTearDown(container.dispose);

    final notifier = container.read(browserProvider.notifier);
    notifier.closeTab(notifier.state.activeTabId!);

    expect(notifier.state.tabs.length, 1);
    expect(notifier.state.tabs.single.url, BrowserNotifier.blankUrl);
  });

  test('initialize 恢复 URL 并选中 activeUrl', () {
    final store = InMemorySessionStore();
    final container = makeContainer(store);
    addTearDown(container.dispose);

    final notifier = container.read(browserProvider.notifier);
    notifier.initialize(['https://a.com', 'https://b.com'], 'https://b.com');

    expect(notifier.state.tabs.map((t) => t.url), ['https://a.com', 'https://b.com']);
    expect(notifier.state.activeTab?.url, 'https://b.com');
  });

  test('标签变化 300ms 后写入会话', () {
    fakeAsync((async) {
      final store = InMemorySessionStore();
      final container = makeContainer(store);
      final notifier = container.read(browserProvider.notifier);

      notifier.openTab('https://a.com');
      async.elapse(const Duration(milliseconds: 350));

      expect(store.saveCount, greaterThan(0));
      expect(store.data?.urls, contains('https://a.com'));

      container.dispose();
    });
  });
}
