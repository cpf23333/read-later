import 'package:dio/dio.dart';

import 'html_meta.dart';

/// 页面元信息（标题、favicon）。
class PageMeta {
  final String? title;
  final String? iconUrl;

  const PageMeta({this.title, this.iconUrl});
}

/// 页面元信息解析接口（便于测试替换）。
abstract class PageMetaResolver {
  Future<PageMeta> resolve(String url);
}

/// 通过 HTTP 拉取目标页并解析标题/favicon；失败返回空元信息，不抛异常。
class TitleResolver implements PageMetaResolver {
  TitleResolver(this._dio);

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  final Dio _dio;

  @override
  Future<PageMeta> resolve(String url) async {
    try {
      final response = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'User-Agent': _userAgent,
            'Accept': 'text/html,application/xhtml+xml',
          },
          receiveTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 5),
        ),
      );

      final body = response.data;
      if (body == null || body.isEmpty) {
        return const PageMeta();
      }

      return PageMeta(
        title: parseTitle(body),
        iconUrl: parseIconUrl(body, Uri.parse(url)),
      );
    } catch (_) {
      return const PageMeta();
    }
  }
}
