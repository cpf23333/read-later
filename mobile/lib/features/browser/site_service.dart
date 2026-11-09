import '../../core/api/api_client.dart';
import '../../core/api/errors.dart';
import '../../core/models/site.dart';
import '../../core/util/origin.dart';
import '../../core/web/title_resolver.dart';

/// 收藏主站的草稿数据。
class SiteDraft {
  final String origin;
  final String title;
  final String? iconUrl;
  final bool exists;
  final bool inTrash;

  const SiteDraft({
    required this.origin,
    required this.title,
    this.iconUrl,
    required this.exists,
    required this.inTrash,
  });
}

/// 站点收藏链路：origin 计算、标题/图标解析、保存。
class SiteService {
  SiteService(this._api, this._resolver);

  final ApiClient _api;
  final PageMetaResolver _resolver;

  Future<SiteDraft> prepare(String pageUrl) async {
    final origin = originOf(pageUrl);
    if (origin == null) {
      throw const ValidationException('当前页面不是网站');
    }

    final existsFuture = _api.siteExists(origin);
    final metaFuture = _resolver.resolve(origin);

    final exists = await existsFuture;
    final meta = await metaFuture;

    final host = hostOf(origin) ?? origin;
    final title = (meta.title?.trim().isNotEmpty ?? false) ? meta.title!.trim() : host;

    return SiteDraft(
      origin: origin,
      title: title,
      iconUrl: meta.iconUrl ?? '$origin/favicon.ico',
      exists: exists.exists,
      inTrash: exists.inTrash,
    );
  }

  Future<Site> save(SiteDraft draft) {
    return _api.addSite(SiteInput(
      url: draft.origin,
      title: draft.title,
      iconUrl: draft.iconUrl,
    ));
  }
}
