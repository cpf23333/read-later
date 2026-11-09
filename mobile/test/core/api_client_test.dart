import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/api/api_client.dart';
import 'package:readlater/core/api/dio_api_client.dart';
import 'package:readlater/core/api/errors.dart';
import 'package:readlater/core/config/config_store.dart';
import 'package:readlater/core/models/link.dart';

import '../support/fake_http_adapter.dart';
import '../support/fakes.dart';

ApiClient buildClient(FakeHttpAdapter adapter, {ConfigStore? configStore}) {
  final dio = Dio()..httpClientAdapter = adapter;
  return DioApiClient(
    dio,
    configStore ?? fakeConfigStore(baseUrl: 'http://s', apiKey: 'k'),
  );
}

void main() {
  test('listLinks 解析嵌套 data.data 与 total，并带 Bearer 头', () async {
    final adapter = FakeHttpAdapter({
      'GET http://s/api/links?page=1&pageSize=50&sortBy=created_at&sortOrder=desc': (options) =>
          jsonResponse(200, {
            'success': true,
            'data': {
              'data': [
                {
                  'id': '1',
                  'url': 'https://a.com',
                  'title': 'A',
                  'nearby_image': '/images/x.jpg',
                  'created_at': 1,
                }
              ],
              'total': 1,
            },
          }),
    });
    final client = buildClient(adapter);

    final page = await client.listLinks();

    expect(page.total, 1);
    expect(page.links.single.title, 'A');
    expect(page.links.single.nearbyImage, 'http://s/images/x.jpg');
    expect(adapter.requests.single.headers['Authorization'], 'Bearer k');
  });

  test('401 映射为 AuthException', () async {
    final adapter = FakeHttpAdapter({
      'GET http://s/api/links?page=1&pageSize=50&sortBy=created_at&sortOrder=desc': (options) =>
          jsonResponse(401, {'success': false, 'error': 'Unauthorized'}),
    });
    final client = buildClient(adapter);

    expect(client.listLinks(), throwsA(isA<AuthException>()));
  });

  test('未配置时抛 NotConfiguredException', () async {
    final adapter = FakeHttpAdapter({});
    final client = buildClient(adapter, configStore: ConfigStore(InMemoryKeyValueStore()));

    expect(client.listSites(), throwsA(isA<NotConfiguredException>()));
  });

  test('addLink 发送 snake_case body', () async {
    final adapter = FakeHttpAdapter({
      'POST http://s/api/links': (options) => jsonResponse(200, {'success': true}),
    });
    final client = buildClient(adapter);

    await client.addLink(const AddLinkRequest(
      url: 'https://a.com',
      title: 'A',
      nearbyImage: 'data:x',
      sourcePage: 'https://b.com',
    ));

    final raw = adapter.requests.single.data;
    final body = raw is String
        ? jsonDecode(raw) as Map<String, dynamic>
        : Map<String, dynamic>.from(raw as Map);
    expect(body['nearby_image'], 'data:x');
    expect(body['source_page'], 'https://b.com');
    expect(body.containsKey('screenshot'), isFalse);
  });

  test('siteExists 解析 inTrash', () async {
    final adapter = FakeHttpAdapter({
      'GET http://s/api/sites/exists?url=https%3A%2F%2Fa.com': (options) =>
          jsonResponse(200, {
            'success': true,
            'data': {'exists': false, 'inTrash': true},
          }),
    });
    final client = buildClient(adapter);

    final result = await client.siteExists('https://a.com');

    expect(result.inTrash, isTrue);
  });

  test('listSites 解析站点列表', () async {
    final adapter = FakeHttpAdapter({
      'GET http://s/api/sites': (options) => jsonResponse(200, {
            'success': true,
            'data': [
              {
                'id': '1',
                'url': 'https://a.com',
                'title': 'A',
                'icon_url': 'https://a.com/f.ico',
                'created_at': 1,
              }
            ],
          }),
    });
    final client = buildClient(adapter);

    final sites = await client.listSites();

    expect(sites.single.iconUrl, 'https://a.com/f.ico');
  });

  test('deleteSite 使用 DELETE /api/sites/:id', () async {
    final adapter = FakeHttpAdapter({
      'DELETE http://s/api/sites/1': (options) => jsonResponse(200, {'success': true}),
    });
    final client = buildClient(adapter);

    await client.deleteSite('1');

    expect(adapter.requests.single.method, 'DELETE');
  });
}
