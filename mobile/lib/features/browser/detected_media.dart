/// 页面内检测到的可播放媒体。
class DetectedMedia {
  final String url;
  final String type;
  final String title;
  final String sourcePage;
  final String userAgent;

  const DetectedMedia({
    required this.url,
    this.type = '',
    this.title = '',
    this.sourcePage = '',
    this.userAgent = '',
  });

  factory DetectedMedia.fromMap(Map<String, dynamic> map) {
    return DetectedMedia(
      url: (map['url'] as String?) ?? '',
      type: (map['type'] as String?) ?? '',
      title: (map['title'] as String?) ?? '',
      sourcePage: (map['sourcePage'] as String?) ?? '',
      userAgent: (map['ua'] as String?) ?? '',
    );
  }

  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    final host = Uri.tryParse(url)?.host;
    return host == null || host.isEmpty ? url : host;
  }
}
