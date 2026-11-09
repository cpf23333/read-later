import 'package:dio/dio.dart';

import '../api/errors.dart';
import '../config/config_store.dart';
import '../models/config.dart';
import '../models/health.dart';
import '../models/link.dart';
import '../models/site.dart';
import 'api_client.dart';

/// Dio 实现的服务器 API 客户端。
class DioApiClient implements ApiClient {
  DioApiClient(this._dio, this._configStore);

  final Dio _dio;
  final ConfigStore _configStore;

  static const _defaultTimeout = Duration(seconds: 10);
  static const _addLinkTimeout = Duration(seconds: 30);

  Future<ServerConfig> _requireConfig() async {
    final config = await _configStore.read();
    if (!config.isConfigured) {
      throw const NotConfiguredException();
    }
    return config;
  }

  Uri _buildUri(String baseUrl, String path, [Map<String, dynamic>? query]) {
    final uri = Uri.parse('$baseUrl$path');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: query);
  }

  Options _options(String apiKey, {required String method, required Duration timeout}) {
    return Options(
      method: method,
      headers: {'Authorization': 'Bearer $apiKey'},
      sendTimeout: timeout,
      receiveTimeout: timeout,
    );
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? data,
    Duration timeout = _defaultTimeout,
  }) async {
    final config = await _requireConfig();
    try {
      final response = await _dio.requestUri<dynamic>(
        _buildUri(config.baseUrl, path, query),
        data: data,
        options: _options(config.apiKey, method: method, timeout: timeout),
      );
      final body = response.data;
      if (body is Map<String, dynamic>) return body;
      return {'success': true, 'data': body};
    } on DioException catch (e) {
      throw _mapException(e);
    }
  }

  Map<String, dynamic> _unwrap(Map<String, dynamic> body) {
    if (body['success'] == false) {
      throw ValidationException((body['error'] as String?) ?? '请求失败');
    }
    return body;
  }

  ApiException _mapException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const NetworkException('请求超时');
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        final message = _serverErrorMessage(e.response?.data);
        if (code == 401) return const AuthException();
        if (code == 400) return ValidationException(message ?? '请求参数错误');
        if (code != null && code >= 500) return ServerException(message ?? '服务器错误');
        return NetworkException(message ?? '请求失败');
      case DioExceptionType.connectionError:
      case DioExceptionType.badCertificate:
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
        return const NetworkException();
    }
  }

  String? _serverErrorMessage(dynamic data) {
    if (data is Map && data['error'] is String) {
      return data['error'] as String;
    }
    return null;
  }

  @override
  Future<HealthStatus> health() async {
    final body = await _request('GET', '/api/health', timeout: const Duration(seconds: 5));
    return HealthStatus(ok: body['success'] == true);
  }

  @override
  Future<ExistsResult> linkExists(String url) async {
    final body = _unwrap(
      await _request('GET', '/api/links/exists', query: {'url': url}),
    );
    final data = body['data'];
    return ExistsResult.fromJson(data is Map<String, dynamic> ? data : const {'exists': false});
  }

  @override
  Future<void> addLink(AddLinkRequest req) async {
    final body = await _request('POST', '/api/links', data: req.toJson(), timeout: _addLinkTimeout);
    _unwrap(body);
  }

  @override
  Future<PagedLinks> listLinks({
    int page = 1,
    int pageSize = 50,
    String? search,
    String? domain,
    String sortBy = 'created_at',
    String sortOrder = 'desc',
  }) async {
    final body = _unwrap(await _request('GET', '/api/links', query: {
      'page': '$page',
      'pageSize': '$pageSize',
      'sortBy': sortBy,
      'sortOrder': sortOrder,
      if (search != null && search.isNotEmpty) 'search': search,
      if (domain != null && domain.isNotEmpty) 'domain': domain,
    }));
    final data = body['data'];
    final links = data is List
        ? data.whereType<Map<String, dynamic>>().map(LinkItem.fromJson).toList()
        : <LinkItem>[];
    final total = (body['total'] as num?)?.toInt() ?? links.length;
    final baseUrl = (await _configStore.read()).baseUrl;
    return PagedLinks(
      links: links.map((link) => _resolveLinkImages(link, baseUrl)).toList(),
      total: total,
    );
  }

  String? _resolvePath(String? path, String baseUrl) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://') || path.startsWith('data:')) {
      return path;
    }
    if (path.startsWith('/')) return '$baseUrl$path';
    return path;
  }

  LinkItem _resolveLinkImages(LinkItem link, String baseUrl) {
    return LinkItem(
      id: link.id,
      url: link.url,
      title: link.title,
      nearbyImage: _resolvePath(link.nearbyImage, baseUrl),
      screenshot: _resolvePath(link.screenshot, baseUrl),
      sourcePage: link.sourcePage,
      createdAt: link.createdAt,
      customData: link.customData,
    );
  }

  TrashItem _resolveTrashImages(TrashItem item, String baseUrl) {
    return TrashItem(
      id: item.id,
      linkId: item.linkId,
      url: item.url,
      title: item.title,
      nearbyImage: _resolvePath(item.nearbyImage, baseUrl),
      screenshot: _resolvePath(item.screenshot, baseUrl),
      sourcePage: item.sourcePage,
      createdAt: item.createdAt,
      deletedAt: item.deletedAt,
    );
  }

  @override
  Future<void> deleteLink(String id) async {
    _unwrap(await _request('DELETE', '/api/links/$id'));
  }

  @override
  Future<List<TrashItem>> listTrash() async {
    final body = _unwrap(await _request('GET', '/api/trash'));
    final data = body['data'];
    final items = data is List
        ? data.whereType<Map<String, dynamic>>().map(TrashItem.fromJson).toList()
        : <TrashItem>[];
    final baseUrl = (await _configStore.read()).baseUrl;
    return items.map((item) => _resolveTrashImages(item, baseUrl)).toList();
  }

  @override
  Future<void> restoreTrash(String id) async {
    _unwrap(await _request('POST', '/api/trash/$id/restore'));
  }

  @override
  Future<void> purgeTrash(String id) async {
    _unwrap(await _request('DELETE', '/api/trash/$id'));
  }

  @override
  Future<List<Site>> listSites() async {
    final body = _unwrap(await _request('GET', '/api/sites'));
    final data = body['data'];
    return data is List
        ? data.whereType<Map<String, dynamic>>().map(Site.fromJson).toList()
        : <Site>[];
  }

  @override
  Future<Site> addSite(SiteInput input) async {
    final body = _unwrap(await _request('POST', '/api/sites', data: {
      'url': input.url,
      'title': input.title,
      if (input.iconUrl != null) 'icon_url': input.iconUrl,
    }));
    final data = body['data'];
    return Site.fromJson(data is Map<String, dynamic> ? data : const {});
  }

  @override
  Future<void> deleteSite(String id) async {
    _unwrap(await _request('DELETE', '/api/sites/$id'));
  }

  @override
  Future<List<Site>> listSiteTrash() async {
    final body = _unwrap(await _request('GET', '/api/sites/trash'));
    final data = body['data'];
    return data is List
        ? data.whereType<Map<String, dynamic>>().map(Site.fromJson).toList()
        : <Site>[];
  }

  @override
  Future<void> restoreSite(String id) async {
    _unwrap(await _request('POST', '/api/sites/$id/restore'));
  }

  @override
  Future<void> purgeSite(String id) async {
    _unwrap(await _request('DELETE', '/api/sites/trash/$id'));
  }

  @override
  Future<SiteExistsResult> siteExists(String url) async {
    final body = _unwrap(
      await _request('GET', '/api/sites/exists', query: {'url': url}),
    );
    final data = body['data'];
    return SiteExistsResult.fromJson(
      data is Map<String, dynamic> ? data : const {'exists': false, 'inTrash': false},
    );
  }
}
