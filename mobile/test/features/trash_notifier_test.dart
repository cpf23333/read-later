import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/models/link.dart';
import 'package:readlater/core/models/site.dart';
import 'package:readlater/providers.dart';

import '../support/fakes.dart';

void main() {
  test('load 同时拉取链接与站点回收站', () async {
    final api = FakeApiClient(
      trash: [
        const TrashItem(
          id: 't1',
          linkId: 'l1',
          url: 'https://a.com',
          title: '旧链接',
          createdAt: 1,
          deletedAt: 2,
        ),
      ],
      siteTrash: [
        const Site(id: 's1', url: 'https://a.com', title: '站点', createdAt: 1),
      ],
    );
    final container = ProviderContainer(overrides: [apiClientProvider.overrideWithValue(api)]);
    addTearDown(container.dispose);

    await container.read(trashProvider.notifier).load();

    final state = container.read(trashProvider);
    expect(state.links.length, 1);
    expect(state.sites.length, 1);
    expect(state.loading, isFalse);
  });

  test('restoreSite 调用 api 并从列表移除', () async {
    final api = FakeApiClient(
      siteTrash: [const Site(id: 's1', url: 'https://a.com', title: '站点', createdAt: 1)],
    );
    final container = ProviderContainer(overrides: [apiClientProvider.overrideWithValue(api)]);
    addTearDown(container.dispose);
    await container.read(trashProvider.notifier).load();

    await container.read(trashProvider.notifier).restoreSite('s1');

    expect(container.read(trashProvider).sites, isEmpty);
  });

  test('purgeLink 从列表移除', () async {
    final api = FakeApiClient(
      trash: [
        const TrashItem(
          id: 't1',
          linkId: 'l1',
          url: 'https://a.com',
          title: '旧链接',
          createdAt: 1,
          deletedAt: 2,
        ),
      ],
    );
    final container = ProviderContainer(overrides: [apiClientProvider.overrideWithValue(api)]);
    addTearDown(container.dispose);
    await container.read(trashProvider.notifier).load();

    await container.read(trashProvider.notifier).purgeLink('t1');

    expect(container.read(trashProvider).links, isEmpty);
  });
  test('batchRestoreLinks 调用批量接口并移除', () async {
    final api = FakeApiClient(
      trash: [
        const TrashItem(
          id: 't1',
          linkId: 'l1',
          url: 'https://a.com',
          title: 'A',
          createdAt: 1,
          deletedAt: 2,
        ),
        const TrashItem(
          id: 't2',
          linkId: 'l2',
          url: 'https://b.com',
          title: 'B',
          createdAt: 1,
          deletedAt: 2,
        ),
      ],
    );
    final container = ProviderContainer(overrides: [apiClientProvider.overrideWithValue(api)]);
    addTearDown(container.dispose);
    await container.read(trashProvider.notifier).load();

    await container.read(trashProvider.notifier).batchRestoreLinks(['t1']);

    expect(container.read(trashProvider).links.map((t) => t.id), ['t2']);
    expect(api.batchRestoredTrashIds.single, ['t1']);
  });
}
