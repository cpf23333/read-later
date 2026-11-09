import '../../core/api/api_client.dart';
import '../../core/logging/app_logger.dart';
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
  final String? existingId;

  const LinkPreview({
    required this.url,
    required this.title,
    this.nearbyImage,
    required this.sourcePage,
    required this.exists,
    this.existingTitle,
    this.existingId,
  });

  LinkPreview copyWith({String? nearbyImage}) {
    return LinkPreview(
      url: url,
      title: title,
      nearbyImage: nearbyImage ?? this.nearbyImage,
      sourcePage: sourcePage,
      exists: exists,
      existingTitle: existingTitle,
      existingId: existingId,
    );
  }
}

/// 图片/截图 8MB 上限处理结果。
class MediaCaps {
  final String? nearbyImage;
  final String? screenshot;
  final bool droppedImage;
  final bool droppedScreenshot;

  const MediaCaps({
    this.nearbyImage,
    this.screenshot,
    this.droppedImage = false,
    this.droppedScreenshot = false,
  });

  bool get droppedAny => droppedImage || droppedScreenshot;
}

/// 超过上限时先丢截图，再丢附近图片。
MediaCaps applyMediaCaps({
  String? nearbyImage,
  String? screenshot,
  int maxBytes = 8 * 1024 * 1024,
}) {
  final imageLength = nearbyImage?.length ?? 0;
  final screenshotLength = screenshot?.length ?? 0;
  if (imageLength + screenshotLength <= maxBytes) {
    return MediaCaps(nearbyImage: nearbyImage, screenshot: screenshot);
  }

  var cappedImage = nearbyImage;
  var cappedScreenshot = screenshot;
  var droppedImage = false;
  var droppedScreenshot = false;

  if (cappedScreenshot != null) {
    cappedScreenshot = null;
    droppedScreenshot = true;
  }
  if ((cappedImage?.length ?? 0) > maxBytes) {
    cappedImage = null;
    droppedImage = true;
  }

  return MediaCaps(
    nearbyImage: cappedImage,
    screenshot: cappedScreenshot,
    droppedImage: droppedImage,
    droppedScreenshot: droppedScreenshot,
  );
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
      existingId: exists.link?.id,
    );
  }

  /// 返回是否真的写入了服务器（已收藏时不写入）。
  Future<bool> save(LinkPreview preview, {String? screenshotBase64}) async {
    if (preview.exists) return false;

    AppLogger.d(
      'save link: nearbyImage=${preview.nearbyImage?.length} screenshot=${screenshotBase64?.length}',
    );
    await _api.addLink(AddLinkRequest(
      url: preview.url,
      title: preview.title,
      nearbyImage: preview.nearbyImage,
      screenshot: screenshotBase64,
      sourcePage: preview.sourcePage,
      customData: const {'kind': 'link', 'platform': 'android'},
    ));
    return true;
  }

  /// 已收藏时刷新标题/图片/截图，返回是否更新成功。
  Future<bool> updateExisting(
    LinkPreview preview, {
    String? screenshotBase64,
  }) async {
    final id = preview.existingId;
    if (!preview.exists || id == null || id.isEmpty) return false;

    AppLogger.d(
      'update link $id: nearbyImage=${preview.nearbyImage?.length} screenshot=${screenshotBase64?.length}',
    );
    await _api.updateLink(
      id,
      title: preview.title,
      nearbyImage: preview.nearbyImage,
      screenshot: screenshotBase64,
    );
    return true;
  }

  String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }
}
