/// 服务器配置（只存服务器地址与 API Key）。
class ServerConfig {
  final String baseUrl;
  final String apiKey;
  final bool enabled;

  const ServerConfig({
    this.baseUrl = '',
    this.apiKey = '',
    this.enabled = false,
  });

  bool get isConfigured => enabled && baseUrl.isNotEmpty && apiKey.isNotEmpty;

  ServerConfig copyWith({String? baseUrl, String? apiKey, bool? enabled}) {
    return ServerConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'enabled': enabled,
  };

  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    return ServerConfig(
      baseUrl: json['baseUrl'] as String? ?? '',
      apiKey: json['apiKey'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
    );
  }
}
