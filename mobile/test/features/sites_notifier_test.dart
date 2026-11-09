import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/api/errors.dart';
import 'package:readlater/core/models/site.dart';
import 'package:readlater/providers.dart';

import '../support/fakes.dart';

void main() {
  test('refresh 加载站点列表', () async {
    final api = FakeApiClient(
      sites: [const Site(id: 's1', url: 'https://a.com', title: '站点', createdAt: 1)],
    );
    final container = ProviderContainer(overrides: [apiClientProvider.overrideWithValue(api)]);
    addTearDown(container.dispose);

    await container.read(sitesProvider.notifier).refresh();

    expect(container.read(sitesProvider).sites.single.title, '站点');
    expect(container.read(sitesProvider).loading, isFalse);
  });

  test('deleteSite 乐观移除，失败时回滚', () async {
    final api = FakeApiClient(
      sites: [
        const Site(id: 's1', url: 'https://a.com', title: 'A', createdAt: 1),
        const Site(id: 's2', url: 'https://b.com', title: 'B', createdAt: 2),
      ],
    );
    final container = ProviderContainer(overrides: [apiClientProvider.overrideWithValue(api)]);
    addTearDown(container.dispose);
    await container.read(sitesProvider.notifier).refresh();

    api.error = const NetworkException();
    await container.read(sitesProvider.notifier).deleteSite('s1');

    final state = container.read(sitesProvider);
    expect(state.sites.map((s) => s.id), ['s1', 's2']);
    expect(state.error, isNotNull);
  });
}
