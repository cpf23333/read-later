/// User-Agent 配置。
class UserAgentRule {
  final String mode;
  final String? customUserAgent;

  const UserAgentRule({this.mode = 'default', this.customUserAgent});

  bool get isDefault => mode == 'default';

  String get label {
    switch (mode) {
      case 'desktop':
        return '桌面版';
      case 'custom':
        return '自定义';
      default:
        return '默认';
    }
  }

  factory UserAgentRule.fromJson(Map<String, dynamic> json) {
    final mode = json['user_agent_mode'] as String?;
    return UserAgentRule(
      mode: mode == 'desktop' || mode == 'custom' ? mode! : 'default',
      customUserAgent: json['user_agent'] as String?,
    );
  }
}
