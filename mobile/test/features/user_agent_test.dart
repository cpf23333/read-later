import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/models/site.dart';
import 'package:readlater/features/browser/user_agent.dart';

Site _site({
  required String url,
  String mode = 'default',
  String? userAgent,
}) {
  return Site(
    id: url,
    url: url,
    title: url,
    userAgentMode: mode,
    userAgent: userAgent,
    createdAt: 1,
  );
}

void main() {
  test('默认模式不覆盖 UA', () {
    expect(
      userAgentForUrl('https://example.com/a', [_site(url: 'https://example.com')]),
      isNull,
    );
  });

  test('桌面模式返回桌面 UA，忽略 www 前缀', () {
    final ua = userAgentForUrl(
      'https://www.example.com/a',
      [_site(url: 'https://example.com', mode: 'desktop')],
    );
    expect(ua, desktopUserAgent);
  });

  test('自定义模式返回自定义 UA', () {
    final ua = userAgentForUrl(
      'https://example.com/a',
      [_site(url: 'https://example.com', mode: 'custom', userAgent: 'MyAgent')],
    );
    expect(ua, 'MyAgent');
  });

  test('不同域名不匹配', () {
    expect(
      userAgentForUrl(
        'https://other.com/a',
        [_site(url: 'https://example.com', mode: 'desktop')],
      ),
      isNull,
    );
  });
}
