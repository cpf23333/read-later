import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 标签 id → WebView 控制器（控制器不适合放进不可变状态）。
class TabRegistry {
  final Map<String, InAppWebViewController> _controllers = {};

  void register(String tabId, InAppWebViewController controller) {
    _controllers[tabId] = controller;
  }

  void unregister(String tabId) {
    _controllers.remove(tabId);
  }

  InAppWebViewController? of(String tabId) => _controllers[tabId];
}
