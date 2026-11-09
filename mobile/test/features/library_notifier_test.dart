import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/api/errors.dart';
import 'package:readlater/core/models/link.dart';
import 'package:readlater/providers.dart';

import '../support/fakes.dart';

LinkItem link(String id, {String title = 'A', int createdAt = 1}) {
  return LinkItem(id: id, url: 'https://a.com/$id', title: title, createdAt: createdAt);
}

ProviderContainer makeContainer(FakeApiClient api) {
  return ProviderContainer(overrides: [apiClientProvider.overrideWithValue(api)]);
}

void main() {
  test('refresh 填充列表', () async {
    final api = FakeApiClient(links: [link('1'), link('2')], total: 2);
    final container = makeContainer(api);
    addTearDown(container.dispose);

    await container.read(libraryProvider.notifier).refresh();

    final state = container.read(libraryProvider);
    expect(state.links.length, 2);
    expect(state.total, 2);
    expect(state.loading, isFalse);
  });

  test('loadMore 追加下一页并按 id 去重', () async {
    final api = FakeApiClient(links: [link('1')], total: 3);
    final container = makeContainer(api);
    addTearDown(container.dispose);
    final notifier = container.read(libraryProvider.notifier);
    await notifier.refresh();

    api.links = [link('1'), link('2')];
    api.total = 3;
    await notifier.loadMore();

    final state = container.read(libraryProvider);
    expect(state.links.map((l) => l.id), ['1', '2']);
    expect(state.page, 2);
  });

  test('deleteLink 立即移除，失败时回滚', () async {
    final api = FakeApiClient(links: [link('1'), link('2')], total: 2);
    final container = makeContainer(api);
    addTearDown(container.dispose);
    final notifier = container.read(libraryProvider.notifier);
    await notifier.refresh();

    api.error = const NetworkException();
    await notifier.deleteLink('2');

    final state = container.read(libraryProvider);
    expect(state.links.map((l) => l.id), ['1', '2']);
    expect(state.error, isNotNull);
  });

  test('setSearch 300ms 后才请求服务器', () {
    final api = FakeApiClient(links: [link('1')]);
    final container = makeContainer(api);
    addTearDown(container.dispose);
    final notifier = container.read(libraryProvider.notifier);
    final before = api.listLinksCalls;

    notifier.setSearch('flutter');
    expect(container.read(libraryProvider).search, 'flutter');
    expect(api.listLinksCalls, before);
  });
}
