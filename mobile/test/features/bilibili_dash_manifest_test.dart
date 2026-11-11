import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/features/browser/detected_media.dart';
import 'package:readlater/features/player/bilibili_dash_manifest.dart';

void main() {
  test('DetectedMedia parses Bilibili DASH tracks', () {
    final media = DetectedMedia.fromMap({
      'url': 'https://cdn.example/video.m4s',
      'sourcePage': 'https://www.bilibili.com/video/BV1xx',
      'title': '测试视频',
      'bilibili': {
        'duration': 123.5,
        'video': [
          {
            'baseUrl': 'https://cdn.example/video.m4s?x=1&y=2',
            'bandwidth': 1000,
            'codecs': 'avc1.64001F',
            'width': 1920,
            'height': 1080,
            'segmentBase': {'Initialization': '0-100', 'indexRange': '100-200'},
          },
        ],
        'audio': [
          {
            'baseUrl': 'https://cdn.example/audio.m4s',
            'bandwidth': 128,
            'codecs': 'mp4a.40.2',
          },
        ],
      },
    });

    expect(media.isBilibili, isTrue);
    expect(media.bilibili!.duration, 123.5);
    expect(media.bilibili!.videos.single.width, 1920);
    expect(media.bilibili!.audios.single.codecs, 'mp4a.40.2');
  });

  test('handles Bilibili SegmentBase and segment_base variants', () {
    final media = DetectedMedia.fromMap({
      'url': 'https://cdn.example/video.m4s',
      'bilibili': {
        'duration': 10,
        'video': [
          {
            'baseUrl': 'https://cdn.example/video.m4s',
            'bandwidth': 1000,
            'SegmentBase': {
              'initialization': '0-934',
              'index_range': '935-1406',
            },
          },
        ],
        'audio': const [],
      },
    });

    final track = media.bilibili!.videos.single;
    expect(track.initializationRange, '0-934');
    expect(track.indexRange, '935-1406');
  });

  test('manifest picks highest bitrate and escapes URLs', () {
    final dash = BilibiliDash(
      duration: 60,
      videos: const [
        BilibiliTrack(baseUrl: 'https://cdn.example/low.m4s', bandwidth: 100),
        BilibiliTrack(
          baseUrl: 'https://cdn.example/high.m4s?a=1&b=2',
          bandwidth: 1000,
          codecs: 'avc1.64001F',
          width: 1920,
          height: 1080,
          initializationRange: '0-99',
          indexRange: '100-199',
        ),
      ],
      audios: const [
        BilibiliTrack(baseUrl: 'https://cdn.example/audio.m4s', bandwidth: 128),
      ],
    );

    final manifest = buildBilibiliDashManifest(dash);

    expect(manifest, contains('mediaPresentationDuration="PT60.000S"'));
    expect(manifest, contains('https://cdn.example/high.m4s?a=1&amp;b=2'));
    expect(manifest, isNot(contains('low.m4s')));
    expect(manifest, contains('width="1920"'));
    expect(manifest, contains('height="1080"'));
    expect(manifest, contains('indexRange="100-199"'));
    expect(manifest, contains('Initialization range="0-99"'));
    expect(manifest, contains('audio.m4s'));
  });

  test('manifest works without audio', () {
    final dash = BilibiliDash(
      duration: 10,
      videos: const [BilibiliTrack(baseUrl: 'https://cdn.example/v.m4s')],
      audios: const [],
    );

    final manifest = buildBilibiliDashManifest(dash);
    expect(manifest, contains('contentType="video"'));
    expect(manifest, isNot(contains('contentType="audio"')));
  });
}
