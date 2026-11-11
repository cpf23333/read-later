import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 给 libmpv 的 DASH 分片请求补上 Bilibili 需要的 HTTP 头。
///
/// media_kit 的 httpHeaders 对本地 MPD 内的 BaseURL 分片不保证生效；
/// Bilibili CDN 会按 User-Agent/Referer 返回 403，导致 ffmpeg 报
/// "Failed to recognize file format"。这里在 App 内起一个 loopback 代理，
/// MPD 的 BaseURL 指向代理，由代理带上请求头访问真正的 CDN。
class BilibiliMediaProxy {
  BilibiliMediaProxy._(this._server, this._headers);

  final HttpServer _server;
  final Map<String, String> _headers;

  static Future<BilibiliMediaProxy> start(Map<String, String> headers) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final proxy = BilibiliMediaProxy._(server, headers);
    server.listen(proxy._handle);
    return proxy;
  }

  String rewrite(String url) {
    final encoded = base64Url.encode(utf8.encode(url));
    return 'http://127.0.0.1:${_server.port}/media/$encoded';
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    if (request.method != 'GET' ||
        request.uri.pathSegments.length != 2 ||
        request.uri.pathSegments.first != 'media') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    String target;
    try {
      target = utf8.decode(base64Url.decode(request.uri.pathSegments.last));
    } catch (_) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final outgoing = await client.openUrl('GET', Uri.parse(target));
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
