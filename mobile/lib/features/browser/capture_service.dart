import '../../core/api/api_client.dart';
import '../../core/models/link.dart';
import '../../core/web/title_resolver.dart';

/// 长按/收藏当前页的预览数据。
class LinkPreview {
  final String url;
  final String title;
  final String? nearbyImage;
  final String sourcePage;
  final bool exists;
  final String? existingTitle;

  const LinkPreview({
    required this.url,
    required this.title,
    this.nearbyImage,
    required this.sourcePage,
    required this.exists,
    this.existingTitle,
  });
}

/// 收藏链接链路：标题解析、去重检查、保存。
class CaptureService {
  CaptureService(this._api, this._resolver);

  final ApiClient _api;
  final PageMetaResolver _resolver;

  Future<LinkPreview> prepare({
    required String url,
    String? linkText,
    String? nearbyText,
    String? nearbyImage,
    required String sourcePage,
  }) async {
    final existsFuture = _api.linkExists(url);
    final metaFuture = _resolver.resolve(url);

    final exists = await existsFuture;
    final meta = await metaFuture;

    final title = _firstNonEmpty([
      meta.title,
      linkText,
      nearbyText,
    ]) ??
        url;

    return LinkPreview(
      url: url,
      title: title,
      nearbyImage: nearbyImage,
      sourcePage: sourcePage,
      exists: exists.exists,
      existingTitle: exists.link?.title,
    );
  }

  Future<void> save(LinkPreview preview, {String? screenshotBase64}) async {
    await _api.addLink(AddLinkRequest(
      url: preview.url,
      title: preview.title,
      nearbyImage: preview.nearbyImage,
      screenshot: screenshotBase64,
      sourcePage: preview.sourcePage,
      customData: const {'kind': 'link', 'platform': 'android'},
    ));
  }

  String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }
}
