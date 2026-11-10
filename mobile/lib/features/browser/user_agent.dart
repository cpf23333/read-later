import '../../core/models/site.dart';

/// 桌面版 Chrome User-Agent。
const desktopUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

/// 提取用于匹配站点规则的 host，去掉 www. 前缀。
String? _hostKey(String url) {
  final uri = Uri.tryParse(url);
  final host = uri?.host.toLowerCase();
  if (host == null || host.isEmpty) return null;
  return host.startsWith('www.') ? host.substring(4) : host;
}

/// 根据当前 URL 在站点列表中查找 User-Agent 规则。
/// 返回 null 表示使用 WebView 默认 UA。
String? userAgentForUrl(String url, Iterable<Site> sites) {
  final targetHost = _hostKey(url);
  if (targetHost == null) return null;

  for (final site in sites) {
    if (_hostKey(site.url) != targetHost) continue;
    switch (site.userAgentMode) {
      case 'desktop':
        return desktopUserAgent;
      case 'custom':
        final custom = site.userAgent?.trim() ?? '';
        return custom.isEmpty ? null : custom;
      default:
        return null;
    }
  }
  return null;
}
