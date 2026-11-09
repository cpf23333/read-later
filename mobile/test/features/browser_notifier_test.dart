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

  test('超过 10 个标签时按 LRU 关闭最久未使用的非活动标签', () {
    final store = InMemorySessionStore();
    final container = makeContainer(store);
    addTearDown(container.dispose);

    final notifier = container.read(browserProvider.notifier);
    for (var i = 0; i < 10; i++) {
      notifier.openTab('https://example.com/$i');
    }
    // 重新激活一个较旧的标签，随后再开新标签：被激活的标签不能被 LRU 淘汰。
    final protectedId = notifier.state.tabs[1].id;
    notifier.activate(protectedId);
    notifier.openTab('https://example.com/new');

    expect(notifier.state.tabs.length, BrowserNotifier.maxTabs);
    expect(notifier.state.tabs.any((t) => t.id == protectedId), isTrue,
        reason: '被重新激活的标签不应被 LRU 淘汰');
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

  test('initialize 恢复 URL，只加载活动标签', () {
    final store = InMemorySessionStore();
    final container = makeContainer(store);
    addTearDown(container.dispose);

    final notifier = container.read(browserProvider.notifier);
    notifier.initialize(['https://a.com', 'https://b.com'], 'https://b.com');

    expect(notifier.state.tabs.map((t) => t.url), ['https://a.com', 'https://b.com']);
    expect(notifier.state.activeTab?.url, 'https://b.com');
    expect(notifier.state.tabs[0].loaded, isFalse, reason: '非活动标签懒加载');
    expect(notifier.state.tabs[1].loaded, isTrue);
  });

  test('initialize 不覆盖用户刚打开的新标签', () {
    final store = InMemorySessionStore();
    final container = makeContainer(store);
    addTearDown(container.dispose);

    final notifier = container.read(browserProvider.notifier);
    notifier.openTab('https://opened-by-user.com');
    notifier.initialize(['https://last-session.com'], 'https://last-session.com');

    expect(notifier.state.tabs.length, 2);
    expect(notifier.state.tabs.last.url, 'https://opened-by-user.com');
  });

  test('window.open 创建的标签保留 windowId', () {
    final store = InMemorySessionStore();
    final container = makeContainer(store);
    addTearDown(container.dispose);

    final notifier = container.read(browserProvider.notifier);
    notifier.openTab(BrowserNotifier.blankUrl, windowId: 42);

    expect(notifier.state.activeTab?.windowId, 42);
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
