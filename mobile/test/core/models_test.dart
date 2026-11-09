import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/models/link.dart';
import 'package:readlater/core/models/site.dart';

void main() {
  test('Site.fromJson 解析 icon_url 与时间', () {
    final s = Site.fromJson({
      'id': '1',
      'url': 'https://a.com',
      'title': 'A',
      'icon_url': null,
      'created_at': 100,
      'deleted_at': null,
    });
    expect(s.url, 'https://a.com');
    expect(s.iconUrl, isNull);
    expect(s.createdAt, 100);
  });

  test('LinkItem.fromJson 解析 snake_case 字段', () {
    final item = LinkItem.fromJson({
      'id': '1',
      'url': 'https://a.com',
      'title': 'A',
      'nearby_image': '/images/x.jpg',
      'screenshot': null,
      'source_page': 'https://b.com',
      'created_at': 100,
      'custom_data': '{"k":"v"}',
    });
    expect(item.nearbyImage, '/images/x.jpg');
    expect(item.sourcePage, 'https://b.com');
    expect(item.customData, {'k': 'v'});
  });

  test('AddLinkRequest.toJson 使用 snake_case 并忽略空字段', () {
    final req = AddLinkRequest(
      url: 'https://a.com',
      title: 'A',
      nearbyImage: 'data:x',
      screenshot: 'data:y',
      sourcePage: 'https://b.com',
      customData: {'linkText': 't'},
    );
    final json = req.toJson();
    expect(
      json.keys,
      containsAll(['nearby_image', 'screenshot', 'source_page', 'custom_data']),
    );
    expect(json['nearby_image'], 'data:x');
    expect(json.containsKey('id'), isFalse);
  });

  test('ExistsResult.fromJson 解析可选 link', () {
    final result = ExistsResult.fromJson({
      'exists': true,
      'link': {'id': '1', 'url': 'https://a.com', 'title': 'A', 'created_at': 1},
    });
    expect(result.exists, isTrue);
    expect(result.link?.title, 'A');
  });
}
