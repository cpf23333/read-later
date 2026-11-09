import 'dart:convert';

/// 链接（服务器返回 snake_case）。
class LinkItem {
  final String id;
  final String url;
  final String title;
  final String? nearbyImage;
  final String? screenshot;
  final String? sourcePage;
  final int createdAt;
  final Map<String, Object?>? customData;

  const LinkItem({
    required this.id,
    required this.url,
    required this.title,
    this.nearbyImage,
    this.screenshot,
    this.sourcePage,
    required this.createdAt,
    this.customData,
  });

  factory LinkItem.fromJson(Map<String, dynamic> json) {
    return LinkItem(
      id: json['id'] as String? ?? '',
      url: json['url'] as String? ?? '',
      title: json['title'] as String? ?? '',
      nearbyImage: json['nearby_image'] as String?,
      screenshot: json['screenshot'] as String?,
      sourcePage: json['source_page'] as String?,
      createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
      customData: _parseCustomData(json['custom_data']),
    );
  }
}

Map<String, Object?>? _parseCustomData(dynamic value) {
  if (value == null) return null;
  if (value is Map) return value.cast<String, Object?>();
  if (value is String && value.isNotEmpty) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) return decoded.cast<String, Object?>();
    } catch (_) {
      return null;
    }
  }
  return null;
}

/// 链接分页结果。
class PagedLinks {
  final List<LinkItem> links;
  final int total;

  const PagedLinks({required this.links, required this.total});
}

/// 回收站链接（服务器返回 snake_case）。
class TrashItem {
  final String id;
  final String linkId;
  final String url;
  final String title;
  final String? nearbyImage;
  final String? screenshot;
  final String? sourcePage;
  final int createdAt;
  final int deletedAt;

  const TrashItem({
    required this.id,
    required this.linkId,
    required this.url,
    required this.title,
    this.nearbyImage,
    this.screenshot,
    this.sourcePage,
    required this.createdAt,
    required this.deletedAt,
  });

  factory TrashItem.fromJson(Map<String, dynamic> json) {
    return TrashItem(
      id: json['id'] as String? ?? '',
      linkId: json['link_id'] as String? ?? '',
      url: json['url'] as String? ?? '',
      title: json['title'] as String? ?? '',
      nearbyImage: json['nearby_image'] as String?,
      screenshot: json['screenshot'] as String?,
      sourcePage: json['source_page'] as String?,
      createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
      deletedAt: (json['deleted_at'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 新增链接请求体（发送时转 snake_case）。
class AddLinkRequest {
  final String url;
  final String title;
  final String? nearbyImage;
  final String? screenshot;
  final String? sourcePage;
  final Map<String, Object?>? customData;

  const AddLinkRequest({
    required this.url,
    required this.title,
    this.nearbyImage,
    this.screenshot,
    this.sourcePage,
    this.customData,
  });

  Map<String, Object?> toJson() {
    return {
      'url': url,
      'title': title,
      if (nearbyImage != null) 'nearby_image': nearbyImage,
      if (screenshot != null) 'screenshot': screenshot,
      if (sourcePage != null) 'source_page': sourcePage,
      if (customData != null) 'custom_data': customData,
    };
  }
}

/// 链接存在性检查结果。
class ExistsResult {
  final bool exists;
  final LinkItem? link;

  const ExistsResult({required this.exists, this.link});

  factory ExistsResult.fromJson(Map<String, dynamic> json) {
    final rawLink = json['link'];
    return ExistsResult(
      exists: json['exists'] as bool? ?? false,
      link: rawLink is Map<String, dynamic> ? LinkItem.fromJson(rawLink) : null,
    );
  }
}
