/// 域名统计（/api/domains）。
class DomainStat {
  final String domain;
  final int count;

  const DomainStat({required this.domain, required this.count});

  factory DomainStat.fromJson(Map<String, dynamic> json) {
    return DomainStat(
      domain: json['domain'] as String? ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
}
