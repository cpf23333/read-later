/// 站点（origin 级收藏）。
class Site {
  final String id;
  final String url;
  final String title;
  final String? iconUrl;
  final int createdAt;

  const Site({
    required this.id,
    required this.url,
    required this.title,
    this.iconUrl,
    required this.createdAt,
  });

  factory Site.fromJson(Map<String, dynamic> json) {
    return Site(
      id: json['id'] as String? ?? '',
      url: json['url'] as String? ?? '',
      title: json['title'] as String? ?? '',
      iconUrl: json['icon_url'] as String?,
      createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 新增站点请求体。
class SiteInput {
  final String url;
  final String title;
  final String? iconUrl;

  const SiteInput({required this.url, required this.title, this.iconUrl});
}

/// 站点存在性结果。
class SiteExistsResult {
  final bool exists;
  final bool inTrash;

  const SiteExistsResult({required this.exists, required this.inTrash});

  factory SiteExistsResult.fromJson(Map<String, dynamic> json) {
    return SiteExistsResult(
      exists: json['exists'] as bool? ?? false,
      inTrash: json['inTrash'] as bool? ?? false,
    );
  }
}
