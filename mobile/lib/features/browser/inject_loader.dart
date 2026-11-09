import 'package:flutter/services.dart';

/// 读取注入脚本原文。
Future<String> loadInjectJs(AssetBundle bundle) {
  return bundle.loadString('assets/js/inject.js');
}
