/// 页面内检测到的可播放媒体。
class DetectedMedia {
  final String url;
  final String type;
  final String title;
  final String sourcePage;
  final String userAgent;
  final String cookie;
  final BilibiliDash? bilibili;

  const DetectedMedia({
    required this.url,
    this.type = '',
    this.title = '',
    this.sourcePage = '',
    this.userAgent = '',
    this.cookie = '',
    this.bilibili,
  });

  factory DetectedMedia.fromMap(Map<String, dynamic> map) {
    final dash = map['bilibili'];
    return DetectedMedia(
      url: (map['url'] as String?) ?? '',
      type: (map['type'] as String?) ?? '',
      title: (map['title'] as String?) ?? '',
      sourcePage: (map['sourcePage'] as String?) ?? '',
      userAgent: (map['ua'] as String?) ?? '',
      cookie: (map['cookie'] as String?) ?? '',
      bilibili: dash is Map
          ? BilibiliDash.fromMap(Map<String, dynamic>.from(dash))
          : null,
    );
  }

  DetectedMedia copyWith({String? cookie}) {
    return DetectedMedia(
      url: url,
      type: type,
      title: title,
      sourcePage: sourcePage,
      userAgent: userAgent,
      cookie: cookie ?? this.cookie,
      bilibili: bilibili,
    );
  }

  bool get isBilibili => bilibili != null;

  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    final host = Uri.tryParse(url)?.host;
    return host == null || host.isEmpty ? url : host;
  }
}

/// Bilibili playinfo 中的 DASH 音视频轨。
class BilibiliDash {
  final double duration;
  final List<BilibiliTrack> videos;
  final List<BilibiliTrack> audios;

  const BilibiliDash({
    required this.duration,
    required this.videos,
    required this.audios,
  });

  factory BilibiliDash.fromMap(Map<String, dynamic> map) {
    return BilibiliDash(
      duration: _asDouble(map['duration']),
      videos: _tracks(map['video']),
      audios: _tracks(map['audio']),
    );
  }

  static List<BilibiliTrack> _tracks(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => BilibiliTrack.fromMap(Map<String, dynamic>.from(item)))
        .where((track) => track.baseUrl.isNotEmpty)
        .toList(growable: false);
  }
}

class BilibiliTrack {
  final String baseUrl;
  final List<String> backupUrls;
  final int bandwidth;
  final String codecs;
  final String mimeType;
  final int width;
  final int height;
  final String frameRate;
  final String? initializationRange;
  final String? indexRange;

  const BilibiliTrack({
    required this.baseUrl,
    this.backupUrls = const [],
    this.bandwidth = 0,
    this.codecs = '',
    this.mimeType = '',
    this.width = 0,
    this.height = 0,
    this.frameRate = '',
    this.initializationRange,
    this.indexRange,
  });

  factory BilibiliTrack.fromMap(Map<String, dynamic> map) {
    final segmentBase =
        map['segmentBase'] ?? map['segment_base'] ?? map['SegmentBase'];
    final segment = segmentBase is Map
        ? Map<String, dynamic>.from(segmentBase)
        : const <String, dynamic>{};
    final backups = map['backupUrl'] ?? map['backup_url'];
    return BilibiliTrack(
      baseUrl: _asString(map['baseUrl'] ?? map['base_url']),
      backupUrls: backups is List
          ? backups.map(_asString).where((url) => url.isNotEmpty).toList()
          : const [],
      bandwidth: _asInt(map['bandwidth']),
      codecs: _asString(map['codecs']),
      mimeType: _asString(map['mimeType'] ?? map['mime_type']),
      width: _asInt(map['width']),
      height: _asInt(map['height']),
      frameRate: _asString(map['frameRate'] ?? map['frame_rate']),
      initializationRange: _asString(
        segment['Initialization'] ?? segment['initialization'],
      ),
      indexRange: _asString(segment['indexRange'] ?? segment['index_range']),
    );
  }

  String get id => baseUrl.hashCode.toRadixString(36);
}

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

int _asInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

String _asString(dynamic value) => value == null ? '' : '$value';
