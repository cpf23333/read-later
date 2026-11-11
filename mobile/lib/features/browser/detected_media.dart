/// 页面内检测到的可播放媒体。
///
/// 普通直链使用 [url]；需要音视频分轨的平台可以在 [dash] 中提供 DASH
/// 轨道信息，播放器会生成临时 MPD，并通过本地代理补请求头。
class DetectedMedia {
  final String url;
  final String type;
  final String title;
  final String sourcePage;
  final String userAgent;
  final String cookie;
  final DashPlaylist? dash;

  const DetectedMedia({
    required this.url,
    this.type = '',
    this.title = '',
    this.sourcePage = '',
    this.userAgent = '',
    this.cookie = '',
    this.dash,
  });

  factory DetectedMedia.fromMap(Map<String, dynamic> map) {
    final dash = map['dash'] ?? map['bilibili'];
    return DetectedMedia(
      url: (map['url'] as String?) ?? '',
      type: (map['type'] as String?) ?? '',
      title: (map['title'] as String?) ?? '',
      sourcePage: (map['sourcePage'] as String?) ?? '',
      userAgent: (map['ua'] as String?) ?? '',
      cookie: (map['cookie'] as String?) ?? '',
      dash: dash is Map
          ? DashPlaylist.fromMap(Map<String, dynamic>.from(dash))
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
      dash: dash,
    );
  }

  bool get hasDash => dash != null;

  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    final host = Uri.tryParse(url)?.host;
    return host == null || host.isEmpty ? url : host;
  }
}

/// 一个 DASH 播放清单中的音视频轨道。
class DashPlaylist {
  final double duration;
  final List<DashTrack> videos;
  final List<DashTrack> audios;

  const DashPlaylist({
    required this.duration,
    required this.videos,
    required this.audios,
  });

  factory DashPlaylist.fromMap(Map<String, dynamic> map) {
    return DashPlaylist(
      duration: _asDouble(map['duration']),
      videos: _tracks(map['video']),
      audios: _tracks(map['audio']),
    );
  }

  static List<DashTrack> _tracks(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => DashTrack.fromMap(Map<String, dynamic>.from(item)))
        .where((track) => track.baseUrl.isNotEmpty)
        .toList(growable: false);
  }

  /// 用于代理 host 白名单，避免代理转发任意 URL。
  Set<String> get allowedHosts {
    final hosts = <String>{};
    for (final track in [...videos, ...audios]) {
      final host = Uri.tryParse(track.baseUrl)?.host;
      if (host != null && host.isNotEmpty) hosts.add(host);
    }
    return hosts;
  }
}

class DashTrack {
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

  const DashTrack({
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

  factory DashTrack.fromMap(Map<String, dynamic> map) {
    final segmentBase =
        map['SegmentBase'] ?? map['segmentBase'] ?? map['segment_base'];
    final segment = segmentBase is Map
        ? Map<String, dynamic>.from(segmentBase)
        : const <String, dynamic>{};
    final backups = map['backupUrl'] ?? map['backup_url'];
    return DashTrack(
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
