import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 通用本地媒体请求代理。
///
/// 某些 CDN 的播放清单（MPD/HLS）请求头由播放器自己发出，media_kit 的
/// `httpHeaders` 不保证能传到清单内的分片请求。代理把清单中的 BaseURL
/// 改写到本机 loopback，由 Dart 侧补 User-Agent / Referer / Cookie / Range。
///
/// [allowedHosts] 是安全边界：只允许代理这些 host 及其子域，避免页面注入
/// 的内容把代理当成任意 HTTP 转发器（SSRF）。
class HeaderMediaProxy {
  HeaderMediaProxy._(this._server, this._headers, this._allowedHosts);

  final HttpServer _server;
  final Map<String, String> _headers;
  final Set<String> _allowedHosts;

  static Future<HeaderMediaProxy> start(
    Map<String, String> headers, {
    required Set<String> allowedHosts,
  }) async {
    if (allowedHosts.isEmpty) {
      throw ArgumentError('媒体代理至少需要一个允许的 host');
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final proxy = HeaderMediaProxy._(server, headers, allowedHosts);
    server.listen(proxy._handle);
    return proxy;
  }

  String rewrite(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !_isAllowed(uri.host)) {
      throw ArgumentError('不允许代理的媒体 host: ${uri?.host ?? url}');
    }
    final encoded = base64Url.encode(utf8.encode(url));
    return 'http://127.0.0.1:${_server.port}/media/$encoded';
  }

  Future<void> close() => _server.close(force: true);

  bool _isAllowed(String host) {
    final normalized = host.toLowerCase();
    for (final allowed in _allowedHosts) {
      final value = allowed.toLowerCase();
      if (normalized == value || normalized.endsWith('.$value')) {
        return true;
      }
    }
    return false;
  }

  Future<void> _handle(HttpRequest request) async {
    if (request.method != 'GET' ||
        request.uri.pathSegments.length != 2 ||
        request.uri.pathSegments.first != 'media') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    String target;
    Uri targetUri;
    try {
      target = utf8.decode(base64Url.decode(request.uri.pathSegments.last));
      targetUri = Uri.parse(target);
      if (!_isAllowed(targetUri.host)) {
        throw const FormatException('host not allowed');
      }
    } catch (_) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final outgoing = await client.openUrl('GET', targetUri);
      for (final entry in _headers.entries) {
        if (entry.value.isNotEmpty) {
          outgoing.headers.set(entry.key, entry.value);
        }
      }
      outgoing.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null && range.isNotEmpty) {
        outgoing.headers.set(HttpHeaders.rangeHeader, range);
      }

      final incoming = await outgoing.close();
      final response = request.response;
      response.statusCode = incoming.statusCode;
      const copyHeaders = [
        HttpHeaders.contentTypeHeader,
        HttpHeaders.contentLengthHeader,
        HttpHeaders.contentRangeHeader,
        HttpHeaders.acceptRangesHeader,
        HttpHeaders.etagHeader,
        HttpHeaders.lastModifiedHeader,
      ];
      for (final name in copyHeaders) {
        final value = incoming.headers.value(name);
        if (value != null) response.headers.set(name, value);
      }
      await incoming.pipe(response);
    } catch (error) {
      try {
        request.response.statusCode = HttpStatus.badGateway;
        request.response.write('proxy error: $error');
        await request.response.close();
      } catch (_) {
        // 响应头已经发出时无法再改状态码，忽略。
      }
    } finally {
      client.close(force: true);
    }
  }
}
