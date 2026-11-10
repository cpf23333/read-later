/// 站点（origin 级收藏）。
class Site {
  final String id;
  final String url;
  final String title;
  final String? iconUrl;
  final String userAgentMode;
  final String? userAgent;
  final int createdAt;

  const Site({
    required this.id,
    required this.url,
    required this.title,
    this.iconUrl,
    this.userAgentMode = 'default',
    this.userAgent,
    required this.createdAt,
  });

  factory Site.fromJson(Map<String, dynamic> json) {
    final mode = json['user_agent_mode'] as String?;
    return Site(
      id: json['id'] as String? ?? '',
      url: json['url'] as String? ?? '',
      title: json['title'] as String? ?? '',
      iconUrl: json['icon_url'] as String?,
      userAgentMode: mode == 'desktop' || mode == 'custom' ? mode! : 'default',
      userAgent: json['user_agent'] as String?,
      createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 新增站点请求体。
class SiteInput {
  final String url;
  final String title;
  final String? iconUrl;
  final String userAgentMode;
  final String? userAgent;

  const SiteInput({
    required this.url,
    required this.title,
    this.iconUrl,
    this.userAgentMode = 'default',
    this.userAgent,
  });
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
