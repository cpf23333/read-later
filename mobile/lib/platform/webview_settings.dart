import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// WebView 安全与行为设置（平台差异集中在此）。
InAppWebViewSettings buildWebViewSettings({required bool isAndroid}) {
  return InAppWebViewSettings(
    javaScriptEnabled: true,
    supportMultipleWindows: true,
    javaScriptCanOpenWindowsAutomatically: false,
    allowFileAccess: false,
    allowContentAccess: false,
    allowFileAccessFromFileURLs: false,
    mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
    safeBrowsingEnabled: true,
    useShouldOverrideUrlLoading: true,
    isInspectable: kDebugMode,
    // 长按菜单由注入脚本 + Flutter 自绘，压掉系统菜单。
    disableContextMenu: true,
    allowsLinkPreview: false,
    mediaPlaybackRequiresUserGesture: true,
  );
}
