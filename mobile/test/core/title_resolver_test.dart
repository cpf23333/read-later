import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/web/html_meta.dart';
import 'package:readlater/core/web/title_resolver.dart';

import '../support/fake_http_adapter.dart';

void main() {
  test('parseTitle 优先 og:title 再 title', () {
    expect(
      parseTitle('<title>A</title><meta property="og:title" content="OG">'),
      'OG',
    );
    expect(parseTitle('<title>A</title>'), 'A');
    expect(parseTitle('<html></html>'), isNull);
  });

  test('parseIconUrl 把相对 href 转绝对', () {
    expect(
      parseIconUrl('<link rel="icon" href="/f.ico">', Uri.parse('https://a.com/x')),
      'https://a.com/f.ico',
    );
    expect(
      parseIconUrl('<link rel="shortcut icon" href="f.ico">', Uri.parse('https://a.com/x/')),
      'https://a.com/x/f.ico',
    );
    expect(
      parseIconUrl('<link rel="icon" href="data:,">', Uri.parse('https://a.com/x')),
      isNull,
    );
  });

  test('TitleResolver 解析页面标题与图标', () async {
    final adapter = FakeHttpAdapter({
      'GET https://a.com/x': (options) => ResponseBody.fromString(
            '<html><head><title>A</title>'
            '<meta property="og:title" content="OG"><link rel="icon" href="/f.ico"></head></html>',
            200,
            headers: {
              Headers.contentTypeHeader: ['text/html'],
            },
          ),
    });
    final dio = Dio()..httpClientAdapter = adapter;

    final meta = await TitleResolver(dio).resolve('https://a.com/x');

    expect(meta.title, 'OG');
    expect(meta.iconUrl, 'https://a.com/f.ico');
  });

  test('TitleResolver 失败时返回空元信息', () async {
    final adapter = FakeHttpAdapter({
      'GET https://a.com/x': (options) => jsonResponse(500, {'error': 'boom'}),
    });
    final dio = Dio()..httpClientAdapter = adapter;

    final meta = await TitleResolver(dio).resolve('https://a.com/x');

    expect(meta.title, isNull);
    expect(meta.iconUrl, isNull);
  });
}
