import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/util/origin.dart';

void main() {
  test('originOf 保留 scheme/host/port，去掉 path/query/fragment', () {
    expect(originOf('https://example.com/a?b=1#c'), 'https://example.com');
    expect(originOf('http://example.com:8080/x'), 'http://example.com:8080');
  });

  test('originOf 对非 http(s) 与非法 URL 返回 null', () {
    expect(originOf('about:blank'), isNull);
    expect(originOf('not a url'), isNull);
    expect(originOf('ftp://example.com/x'), isNull);
  });

  test('hostOf 返回 host', () {
    expect(hostOf('https://example.com:8080/a'), 'example.com');
    expect(hostOf('about:blank'), isNull);
  });
}
