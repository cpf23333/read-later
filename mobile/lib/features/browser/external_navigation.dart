import 'package:flutter/material.dart';

/// 浏览器内部处理的 scheme；其余视为"外部应用"。
const Set<String> internalSchemes = {
  'http',
  'https',
  'about',
  'data',
  'blob',
  'javascript',
};

enum ExternalNavigationKind {
  /// http(s)/about/data/blob 等，WebView 内部加载。
  internal,

  /// 用户点击触发的外部 scheme，先确认再启动。
  externalUserGesture,

  /// 页面脚本/重定向自动触发的外部 scheme，直接拦截。
  externalAutomatic,
}

bool isExternalScheme(String? scheme) {
  final value = scheme?.toLowerCase();
  return value != null && value.isNotEmpty && !internalSchemes.contains(value);
}

ExternalNavigationKind classifyNavigation({
  required String? scheme,
  required bool hasGesture,
}) {
  if (!isExternalScheme(scheme)) return ExternalNavigationKind.internal;
  return hasGesture
      ? ExternalNavigationKind.externalUserGesture
      : ExternalNavigationKind.externalAutomatic;
}

/// 弹窗确认是否允许网页启动外部应用；默认拒绝。
Future<bool> confirmExternalLaunch(
  BuildContext context, {
  required String url,
  required String scheme,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('打开外部应用？'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('网页请求通过「$scheme」启动其他应用：'),
          const SizedBox(height: 8),
          SelectableText(url, maxLines: 3),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('打开'),
        ),
      ],
    ),
  );
  return result ?? false;
}
