import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/models/link.dart';
import 'package:readlater/core/models/site.dart';
import 'package:readlater/core/web/title_resolver.dart';
import 'package:readlater/features/browser/capture_service.dart';
import 'package:readlater/features/browser/site_service.dart';

import '../support/fakes.dart';

void main() {
  test('prepare 标题回退顺序：meta.title → linkText → nearbyText → url', () async {
    final api = FakeApiClient();
    final resolver = FakePageMetaResolver(meta: const PageMeta(title: 'Meta'));
    final service = CaptureService(api, resolver);

    final withMeta = await service.prepare(
      url: 'https://a.com',
      linkText: '链接文字',
      nearbyText: '附近文字',
      sourcePage: 'https://b.com',
    );
    expect(withMeta.title, 'Meta');

    resolver.meta = const PageMeta();
    final withLinkText = await service.prepare(
      url: 'https://a.com',
      linkText: '链接文字',
      nearbyText: '附近文字',
      sourcePage: 'https://b.com',
    );
    expect(withLinkText.title, '链接文字');

    final withNearby = await service.prepare(
      url: 'https://a.com',
      nearbyText: '附近文字',
      sourcePage: 'https://b.com',
    );
    expect(withNearby.title, '附近文字');

    final fallback = await service.prepare(url: 'https://a.com', sourcePage: 'https://b.com');
    expect(fallback.title, 'https://a.com');
  });

  test('save 发送 snake_case 与 custom_data', () async {
    final api = FakeApiClient();
    final service = CaptureService(api, FakePageMetaResolver());

    await service.save(
      const LinkPreview(
        url: 'https://a.com',
        title: 'A',
        nearbyImage: 'data:x',
        sourcePage: 'https://b.com',
        exists: false,
      ),
      screenshotBase64: 'data:y',
    );

    final request = api.addedLinks.single;
    expect(request.toJson()['screenshot'], 'data:y');
    expect(request.toJson()['nearby_image'], 'data:x');
    expect(request.customData?['kind'], 'link');
  });

  test('prepare 回传已收藏状态与已有标题', () async {
    final api = FakeApiClient(
      linkExistsResult: const ExistsResult(
        exists: true,
        link: LinkItem(id: '1', url: 'https://a.com', title: '旧标题', createdAt: 1),
      ),
    );
    final service = CaptureService(api, FakePageMetaResolver());

    final preview = await service.prepare(url: 'https://a.com', sourcePage: 'https://b.com');

    expect(preview.exists, isTrue);
    expect(preview.existingTitle, '旧标题');
  });

  test('SiteService.prepare 计算 origin、标题、favicon 与 inTrash', () async {
    final api = FakeApiClient(
      siteExistsResult: const SiteExistsResult(exists: false, inTrash: true),
    );
    final service = SiteService(
      api,
      FakePageMetaResolver(meta: const PageMeta(title: '站点名')),
    );

    final draft = await service.prepare('https://a.com/x/y?z=1');

    expect(draft.origin, 'https://a.com');
    expect(draft.title, '站点名');
    expect(draft.iconUrl, 'https://a.com/favicon.ico');
    expect(draft.inTrash, isTrue);
  });

  test('SiteService.save 调用 addSite', () async {
    final api = FakeApiClient();
    final service = SiteService(api, FakePageMetaResolver());

    await service.save(const SiteDraft(
      origin: 'https://a.com',
      title: '站点',
      iconUrl: 'https://a.com/f.ico',
      exists: false,
      inTrash: false,
    ));

    expect(api.addedSites.single.url, 'https://a.com');
  });
}
