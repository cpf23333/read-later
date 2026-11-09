import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../platform/system_ui.dart';
import '../../platform/webview_settings.dart';
import '../../providers.dart';
import 'browser_state.dart';
import 'inject_loader.dart';

/// 长按链接回调数据（含页面内提取结果）。
class LinkPressPayload {
  final String url;
  final String? text;
  final String sourcePage;
  final String? linkText;
  final String? nearbyText;
  final String? nearbyImage;

  const LinkPressPayload({
    required this.url,
    this.text,
    required this.sourcePage,
    this.linkText,
    this.nearbyText,
    this.nearbyImage,
  });
}

/// 单个标签的 WebView（注入长按检测与提取脚本）。
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
  String? _injectJs;
  Completer<Map<String, dynamic>>? _extractCompleter;

  @override
  void initState() {
    super.initState();
    _loadInjectScript();
  }

  Future<void> _loadInjectScript() async {
    final source = await loadInjectJs(rootBundle);
    if (!mounted) return;
    setState(() => _injectJs = source);
  }

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

  Future<void> _handleLongPress(Map<dynamic, dynamic> data, InAppWebViewController controller) async {
    final url = data['url'];
    if (url is! String || url.isEmpty) return;

    Map<String, dynamic>? extracted;
    try {
      final completer = Completer<Map<String, dynamic>>();
      _extractCompleter = completer;
      await controller.evaluateJavascript(
        source: 'window.__rlExtract(${jsonEncode(url)})',
      );
      extracted = await completer.future.timeout(const Duration(seconds: 4));
    } catch (_) {
      extracted = null;
    } finally {
      _extractCompleter = null;
    }

    if (!mounted) return;
    widget.onLongPressLink?.call(LinkPressPayload(
      url: url,
      text: data['text'] as String?,
      sourcePage: data['sourcePage'] as String? ?? '',
      linkText: extracted?['linkText'] as String?,
      nearbyText: extracted?['nearbyText'] as String?,
      nearbyImage: extracted?['nearbyImage'] as String?,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final injectJs = _injectJs;
    if (injectJs == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final isAndroid = defaultTargetPlatform == TargetPlatform.android;

    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(widget.tab.url)),
      initialSettings: buildWebViewSettings(isAndroid: isAndroid),
      initialUserScripts: UnmodifiableListView<UserScript>([
        UserScript(
          source: injectJs,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: true,
        ),
      ]),
      onWebViewCreated: (controller) {
        controller.addJavaScriptHandler(
          handlerName: 'rl:longPress',
          callback: (args) {
            final map = args.isNotEmpty ? args.first : null;
            if (map is Map) {
              _handleLongPress(map, controller);
            }
            return null;
          },
        );
        controller.addJavaScriptHandler(
          handlerName: 'rl:extractResult',
          callback: (args) {
            final completer = _extractCompleter;
            if (completer != null && !completer.isCompleted) {
              try {
                final raw = args.first;
                if (raw is String) {
                  completer.complete(jsonDecode(raw) as Map<String, dynamic>);
                } else if (raw is Map<String, dynamic>) {
                  completer.complete(raw);
                }
              } catch (_) {
                completer.complete({});
              }
            }
            return null;
          },
        );
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
