/// URL origin 工具：只处理 http(s)。
String? originOf(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;

  final isDefaultPort =
      (uri.scheme == 'http' && uri.port == 80) || (uri.scheme == 'https' && uri.port == 443);
  final portPart = isDefaultPort ? '' : ':${uri.port}';
  return '${uri.scheme}://${uri.host}$portPart';
}

/// 提取 host（仅 http(s)）。
String? hostOf(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri.host;
}
