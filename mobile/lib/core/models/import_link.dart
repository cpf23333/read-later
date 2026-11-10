class ImportLink {
  final String url;
  final String title;
  final String? screenshot;

  const ImportLink({required this.url, this.title = '', this.screenshot});

  Map<String, dynamic> toJson() => {
    'url': url,
    'title': title,
    if (screenshot != null) 'screenshot': screenshot,
  };
}

class ImportResult {
  final int imported;
  final int skipped;
  final int failed;
  final int total;

  const ImportResult({
    required this.imported,
    this.skipped = 0,
    required this.failed,
    required this.total,
  });

  factory ImportResult.fromJson(Map<String, dynamic> json) {
    return ImportResult(
      imported: (json['imported'] as num?)?.toInt() ?? 0,
      skipped: (json['skipped'] as num?)?.toInt() ?? 0,
      failed: (json['failed'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
    );
  }
}

class DedupeResult {
  final int removed;
  final int groups;

  const DedupeResult({required this.removed, required this.groups});

  factory DedupeResult.fromJson(Map<String, dynamic> json) {
    return DedupeResult(
      removed: (json['removed'] as num?)?.toInt() ?? 0,
      groups: (json['groups'] as num?)?.toInt() ?? 0,
    );
  }
}
