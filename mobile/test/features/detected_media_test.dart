import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/features/browser/detected_media.dart';

void main() {
  test('DetectedMedia.fromMap 解析字段', () {
    final media = DetectedMedia.fromMap({
      'url': 'https://cdn.example.com/a.m3u8',
      'type': 'network',
      'title': '示例视频',
      'sourcePage': 'https://example.com/watch',
      'ua': 'Mozilla/5.0',
    });

    expect(media.url, 'https://cdn.example.com/a.m3u8');
    expect(media.type, 'network');
    expect(media.displayTitle, '示例视频');
    expect(media.sourcePage, 'https://example.com/watch');
    expect(media.userAgent, 'Mozilla/5.0');
  });

  test('没有标题时用 host 作为展示名', () {
    const media = DetectedMedia(
      url: 'https://cdn.example.com/video.mp4',
      title: '   ',
    );
    expect(media.displayTitle, 'cdn.example.com');
  });
}
