import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/util/image_data.dart';

void main() {
  test('imageDataUrl 生成服务器可识别的 data URL', () {
    final url = imageDataUrl([1, 2, 3], mimeType: 'image/jpeg');

    expect(url, 'data:image/jpeg;base64,${base64Encode([1, 2, 3])}');
    expect(url.startsWith('data:image/'), isTrue);
  });
}
