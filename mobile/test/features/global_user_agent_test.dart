import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/models/site.dart';
import 'package:readlater/core/models/user_agent_rule.dart';
import 'package:readlater/providers.dart';

import '../support/fakes.dart';

void main() {
  test('加载并保存全局默认 UA', () async {
    final api = FakeApiClient()
      ..defaultUserAgent = const UserAgentRule(mode: 'desktop');
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    await container.read(globalUserAgentProvider.notifier).refresh();
    expect(container.read(globalUserAgentProvider).initialized, isTrue);
    expect(container.read(globalUserAgentProvider).rule.mode, 'desktop');

    await container
        .read(globalUserAgentProvider.notifier)
        .save(const UserAgentRule(mode: 'custom', customUserAgent: 'GlobalUA'));
    expect(
      container.read(globalUserAgentProvider).rule.customUserAgent,
      'GlobalUA',
    );
    expect(api.defaultUserAgent.mode, 'custom');
  });

  test('更新站点标题/图标/UA', () async {
    final site = const Site(
      id: 's1',
      url: 'https://example.com',
      title: 'Old',
      createdAt: 1,
    );
    final api = FakeApiClient(sites: [site]);
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(sitesProvider.notifier).refresh();

    await container
        .read(sitesProvider.notifier)
        .updateSite(
          site,
          title: 'New',
          iconUrl: 'https://example.com/icon.png',
          mode: 'desktop',
        );

    final updated = container.read(sitesProvider).sites.single;
    expect(updated.title, 'New');
    expect(updated.iconUrl, 'https://example.com/icon.png');
    expect(updated.userAgentMode, 'desktop');
    expect(api.updatedSites.single['updateIcon'], isTrue);
  });
}
