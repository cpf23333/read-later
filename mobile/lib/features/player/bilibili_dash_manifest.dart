import '../browser/detected_media.dart';

/// 把 Bilibili playinfo 的 DASH 音视频轨生成一个临时 MPD。
///
/// media_kit/libmpv 可以直接读取本地 MPD，并通过 httpHeaders 给远端分片
/// 带上 Referer/User-Agent/Cookie。Bilibili 的高清视频通常是音视频分离的，
/// 所以这里选最高带宽的视频轨和音频轨，交给 MPV 自己合并播放。
String buildBilibiliDashManifest(
  BilibiliDash dash, {
  String Function(String url)? rewriteBaseUrl,
}) {
  final video = _best(dash.videos);
  final audio = _best(dash.audios);
  if (video == null) {
    throw ArgumentError('Bilibili DASH 没有视频轨');
  }

  final duration = dash.duration > 0 ? dash.duration : 0.0;
  final durationText = 'PT${duration.toStringAsFixed(3)}S';
  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" '
      'profiles="urn:mpeg:dash:profile:isoff-main:2011" '
      'type="static" '
      'mediaPresentationDuration="$durationText" '
      'minBufferTime="PT1.5S">',
    )
    ..writeln('  <Period duration="$durationText">');

  _writeAdaptationSet(
    buffer,
    id: 'video',
    contentType: 'video',
    mimeType: video.mimeType.isEmpty ? 'video/mp4' : video.mimeType,
    track: video,
    rewriteBaseUrl: rewriteBaseUrl,
  );
  if (audio != null) {
    _writeAdaptationSet(
      buffer,
      id: 'audio',
      contentType: 'audio',
      mimeType: audio.mimeType.isEmpty ? 'audio/mp4' : audio.mimeType,
      track: audio,
      rewriteBaseUrl: rewriteBaseUrl,
    );
  }

  buffer
    ..writeln('  </Period>')
    ..writeln('</MPD>');
  return buffer.toString();
}

BilibiliTrack? _best(List<BilibiliTrack> tracks) {
  if (tracks.isEmpty) return null;
  return tracks.reduce(
    (best, track) => track.bandwidth > best.bandwidth ? track : best,
  );
}

void _writeAdaptationSet(
  StringBuffer buffer, {
  required String id,
  required String contentType,
  required String mimeType,
  required BilibiliTrack track,
  String Function(String url)? rewriteBaseUrl,
}) {
  buffer
    ..writeln(
      '    <AdaptationSet id="$id" contentType="$contentType" '
      'mimeType="${_escape(mimeType)}" segmentAlignment="true" '
      'startWithSAP="1">',
    )
    ..writeln(
      '      <Representation id="${track.id}" '
      'bandwidth="${track.bandwidth > 0 ? track.bandwidth : 1}"'
      '${track.codecs.isEmpty ? '' : ' codecs="${_escape(track.codecs)}"'}'
      '${track.width > 0 ? ' width="${track.width}"' : ''}'
      '${track.height > 0 ? ' height="${track.height}"' : ''}'
      '${track.frameRate.isEmpty ? '' : ' frameRate="${_escape(track.frameRate)}"'}>',
    )
    ..writeln(
      '        <BaseURL>'
      '${_escape(rewriteBaseUrl?.call(track.baseUrl) ?? track.baseUrl)}'
      '</BaseURL>',
    );
  if (track.indexRange != null || track.initializationRange != null) {
    buffer.write('        <SegmentBase');
    if (track.indexRange != null) {
      buffer.write(
        ' indexRange="${_escape(track.indexRange!)}" indexRangeExact="true"',
      );
    }
    buffer.write('>');
    if (track.initializationRange != null) {
      buffer.write(
        '<Initialization range="${_escape(track.initializationRange!)}"/>',
      );
    }
    buffer.writeln('</SegmentBase>');
  }
  buffer
    ..writeln('      </Representation>')
    ..writeln('    </AdaptationSet>');
}

String _escape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
