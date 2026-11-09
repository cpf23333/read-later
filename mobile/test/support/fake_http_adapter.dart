import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

typedef FakeHandler = ResponseBody Function(RequestOptions options);

/// 构造 JSON 响应。
ResponseBody jsonResponse(int status, Object body) {
  return ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
}

/// 按 "METHOD uri" 精确匹配的假 HTTP 适配器，并记录收到的请求。
class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter(this.handlers);

  final Map<String, FakeHandler> handlers;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final key = '${options.method} ${options.uri}';
    final handler = handlers[key];
    if (handler == null) {
      return jsonResponse(500, {'success': false, 'error': 'no handler for $key'});
    }
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}
