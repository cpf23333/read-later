import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/config/server_url.dart';

void main() {
  test('补全 http scheme 并去掉末尾斜杠', () {
    expect(normalizeServerUrl('192.168.1.2:3000'), 'http://192.168.1.2:3000');
    expect(
      normalizeServerUrl('http://192.168.1.2:3000/'),
      'http://192.168.1.2:3000',
    );
    expect(normalizeServerUrl('https://example.com'), 'https://example.com');
  });

  test('修正常见全角标点', () {
    expect(
      normalizeServerUrl('http：//127。0。0。1：3998'),
      'http://127.0.0.1:3998',
    );
  });

  test('拒绝非 http(s) 或非法地址', () {
    expect(normalizeServerUrl('abc'), isNull);
    expect(normalizeServerUrl('http://'), isNull);
    expect(normalizeServerUrl('ftp://example.com'), isNull);
    expect(validateServerUrl('abc'), isNotNull);
    expect(validateServerUrl('http://192.168.1.2:3000'), isNull);
  });
}
