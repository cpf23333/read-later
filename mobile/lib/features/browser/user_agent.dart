import '../../core/models/user_agent_rule.dart';

/// 桌面版 Chrome User-Agent。
const desktopUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

/// 把规则转换成实际 UA；null 表示使用 WebView 默认 UA。
String? userAgentForRule(UserAgentRule rule) {
  switch (rule.mode) {
    case 'desktop':
      return desktopUserAgent;
    case 'custom':
      final custom = rule.customUserAgent?.trim() ?? '';
      return custom.isEmpty ? null : custom;
    default:
      return null;
  }
}
