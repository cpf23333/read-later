import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../platform/system_ui.dart';
import '../../platform/webview_settings.dart';
import '../../providers.dart';
import 'browser_state.dart';

/// 长按链接回调数据。
class LinkPressPayload {
  final String url;
  final String? text;
  final String sourcePage;

  const LinkPressPayload({
    required this.url,
    this.text,
    required this.sourcePage,
  });
}

/// 单个标签的 WebView。
class TabWebView extends ConsumerStatefulWidget {
  const TabWebView({
    super.key,
    required this.tab,
    required this.onCreated,
    this.onLongPressLink,
  });

  final BrowserTab tab;
  final void Function(InAppWebViewController controller) onCreated;
  final void Function(LinkPressPayload payload)? onLongPressLink;

  @override
  ConsumerState<TabWebView> createState() => _TabWebViewState();
}

class _TabWebViewState extends ConsumerState<TabWebView> {
  void _update({
    String? url,
    String? title,
    bool? loading,
    bool? canGoBack,
    bool? canGoForward,
  }) {
    ref.read(browserProvider.notifier).updateTab(
          widget.tab.id,
          url: url,
          title: title,
          loading: loading,
          canGoBack: canGoBack,
          canGoForward: canGoForward,
        );
  }

  @override
  Widget build(BuildContext context) {
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;

    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(widget.tab.url)),
      initialSettings: buildWebViewSettings(isAndroid: isAndroid),
      onWebViewCreated: (controller) {
        widget.onCreated(controller);
      },
      onLoadStart: (controller, url) {
        _update(loading: true, url: url?.toString());
      },
      onLoadStop: (controller, url) async {
        _update(
          loading: false,
          url: url?.toString(),
          canGoBack: await controller.canGoBack(),
          canGoForward: await controller.canGoForward(),
        );
      },
      onUpdateVisitedHistory: (controller, url, isReload) async {
        _update(
          url: url?.toString(),
          canGoBack: await controller.canGoBack(),
          canGoForward: await controller.canGoForward(),
        );
      },
      onTitleChanged: (controller, title) {
        if (title != null && title.isNotEmpty) {
          _update(title: title);
        }
      },
      onEnterFullscreen: (controller) {
        enterFullscreen();
      },
      onExitFullscreen: (controller) {
        exitFullscreen();
      },
      onCreateWindow: (controller, action) async {
        final url = action.request.url?.toString();
        if (url != null && url.isNotEmpty) {
          ref.read(browserProvider.notifier).openTab(url);
        }
        return true;
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final url = navigationAction.request.url?.toString() ?? '';
        final scheme = Uri.tryParse(url)?.scheme;
        const internalSchemes = {'http', 'https', 'about', 'data', 'blob', 'javascript'};
        if (scheme != null && !internalSchemes.contains(scheme)) {
          await launchUrl(Uri.parse(url));
          return NavigationActionPolicy.CANCEL;
        }
        return NavigationActionPolicy.ALLOW;
      },
      onDownloadStartRequest: (controller, request) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂不支持下载')),
        );
      },
    );
  }
}
