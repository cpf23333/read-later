import 'dart:convert';
import 'dart:typed_data';

import '../../core/api/api_client.dart';
import '../../core/api/errors.dart';
import '../../core/models/site.dart';
import '../../core/util/origin.dart';
import '../../core/web/title_resolver.dart';
import 'capture_service.dart';

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
  SiteService(this._api, this._resolver, [this._capture]);

  final ApiClient _api;
  final PageMetaResolver _resolver;
  final CaptureService? _capture;

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
    final title = (meta.title?.trim().isNotEmpty ?? false)
        ? meta.title!.trim()
        : host;

    return SiteDraft(
      origin: origin,
      title: title,
      iconUrl: meta.iconUrl ?? '$origin/favicon.ico',
      exists: exists.exists,
      inTrash: exists.inTrash,
    );
  }

  Future<Site> save(SiteDraft draft) async {
    return _api.addSite(
      SiteInput(
        url: draft.origin,
        title: draft.title,
        iconUrl: await prepareIcon(draft.iconUrl),
      ),
    );
  }

  /// 把远程图标下载后上传到自己的服务器，返回服务器 URL。
  Future<String?> prepareIcon(String? source) async {
    final capture = _capture;
    if (capture == null) return null;
    final data = await capture.resolveNearbyImage(source);
    if (data == null) return null;
    try {
      return await _api.uploadImage(
        data,
        filename: 'site-icon',
        purpose: 'site-icon',
      );
    } catch (_) {
      return null;
    }
  }

  /// 上传用户从相册选择的图标，返回服务器 URL。
  Future<String?> uploadIconBytes(Uint8List bytes, String filename) async {
    if (bytes.isEmpty) return null;
    final lower = filename.toLowerCase();
    final mime = lower.endsWith('.png')
        ? 'image/png'
        : lower.endsWith('.webp')
        ? 'image/webp'
        : 'image/jpeg';
    final data = 'data:$mime;base64,${base64Encode(bytes)}';
    return _api.uploadImage(data, filename: filename, purpose: 'site-icon');
  }
}
