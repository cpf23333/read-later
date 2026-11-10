import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/models/site.dart';
import 'package:readlater/core/models/user_agent_rule.dart';
import 'package:readlater/features/browser/global_user_agent.dart';
import 'package:readlater/features/browser/user_agent.dart';

Site _site({required String url, String mode = 'default', String? userAgent}) {
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
  test('站点桌面模式覆盖全局默认', () {
    final ua = resolveUserAgentForUrl('https://www.example.com/a', [
      _site(url: 'https://example.com', mode: 'desktop'),
    ], const UserAgentRule(mode: 'default'));
    expect(ua, desktopUserAgent);
  });

  test('站点默认模式跟随全局默认', () {
    final ua = resolveUserAgentForUrl('https://example.com/a', [
      _site(url: 'https://example.com'),
    ], const UserAgentRule(mode: 'desktop'));
    expect(ua, desktopUserAgent);
  });

  test('无站点规则时使用全局默认', () {
    final ua = resolveUserAgentForUrl(
      'https://other.com/a',
      const [],
      const UserAgentRule(mode: 'custom', customUserAgent: 'GlobalUA'),
    );
    expect(ua, 'GlobalUA');
  });

  test('站点自定义 UA 优先', () {
    final ua = resolveUserAgentForUrl('https://example.com/a', [
      _site(url: 'https://example.com', mode: 'custom', userAgent: 'SiteUA'),
    ], const UserAgentRule(mode: 'desktop'));
    expect(ua, 'SiteUA');
  });
}
