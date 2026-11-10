/// 服务器地址规范化与校验。
///
/// 允许用户省略 scheme（自动补 http://），并把常见全角标点转成 ASCII。
/// 返回 null 表示不是有效的 http(s) 地址。
String? normalizeServerUrl(String input) {
  var value = input
      .trim()
      .replaceAll('：', ':')
      .replaceAll('。', '.')
      .replaceAll('／', '/');
  if (value.isEmpty) return null;

  if (!value.contains('://')) {
    value = 'http://$value';
  }

  final uri = Uri.tryParse(value);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    return null;
  }
  final host = uri.host.toLowerCase();
  final isLocalhost = host == 'localhost';
  final hasDot = host.contains('.');
  final hasPort =
      value.contains(':') && value.lastIndexOf(':') > value.indexOf('://') + 2;
  if (!isLocalhost && !hasDot && !hasPort) {
    return null;
  }
  return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
}

/// 返回给界面的错误提示，null 表示合法。
String? validateServerUrl(String input) {
  if (input.trim().isEmpty) return '请填写服务器地址';
  if (normalizeServerUrl(input) == null) {
    return '请输入有效的 http(s) 地址，例如 http://192.168.1.2:3000';
  }
  return null;
}
