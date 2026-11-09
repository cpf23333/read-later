/// 服务器健康检查结果。
class HealthStatus {
  final bool ok;

  const HealthStatus({required this.ok});

  factory HealthStatus.fromJson(Map<String, dynamic> json) {
    return HealthStatus(ok: json['success'] as bool? ?? json['status'] == 'ok');
  }
}
