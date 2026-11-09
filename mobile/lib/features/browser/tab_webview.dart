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
import 'browser_notifier.dart';
import 'browser_state.dart';
import 'inject_loader.dart';

/// 长按链接回调数据（页面内提取结果通过 Future 并行返回）。
class LinkPressPayload {
  final String url;
  final String? text;
  final String sourcePage;
  final Future<Map<String, dynamic>>? extraction;

  const LinkPressPayload({
    required this.url,
    this.text,
    required this.sourcePage,
    this.extraction,
  });
}

/// 单个标签的 WebView（注入长按检测与提取脚本）。
class TabWebView extends ConsumerStatefulWidget {
  const TabWebView({
    super.key,
    required this.tab,
    required this.onCreated,
    this.onLongPressLink,
    this.active = true,
  });

  final BrowserTab tab;
  final void Function(InAppWebViewController controller) onCreated;
  final void Function(LinkPressPayload payload)? onLongPressLink;
  final bool active;

  @override
  ConsumerState<TabWebView> createState() => _TabWebViewState();
}

class _TabWebViewState extends ConsumerState<TabWebView> {
  String? _injectJs;
  InAppWebViewController? _controller;
  Completer<Map<String, dynamic>>? _extractCompleter;

  @override
  void initState() {
    super.initState();
    _loadInjectScript();
  }

  @override
  void didUpdateWidget(covariant TabWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active && !widget.active) {
      _pauseMedia();
    }
  }

  Future<void> _loadInjectScript() async {
    final source = await loadInjectJs(rootBundle);
    if (!mounted) return;
    setState(() => _injectJs = source);
  }

  Future<void> _pauseMedia() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.evaluateJavascript(source: '''
        (() => {
          document.querySelectorAll('video, audio').forEach((el) => {
            try { el.pause(); } catch (_) {}
          });
        })();
      ''');
    } catch (_) {
      // 页面已销毁等情况忽略。
    }
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

  Future<Map<String, dynamic>> _extract(String url) {
    final controller = _controller;
    if (controller == null) return Future.value(const {});

    final completer = Completer<Map<String, dynamic>>();
    _extractCompleter = completer;
    unawaited(
      controller
          .evaluateJavascript(source: 'window.__rlExtract(${jsonEncode(url)})')
          .catchError((Object _) {
        if (!completer.isCompleted) completer.complete(const {});
        return true;
      }),
    );

    return completer.future.timeout(
      const Duration(seconds: 4),
      onTimeout: () => const {},
    );
  }

  void _handleLongPress(Map<dynamic, dynamic> data) {
    final url = data['url'];
    if (url is! String || url.isEmpty) return;

    // 立即把 payload 交给 UI（sheet 先显示加载态），提取在后台并行完成。
    widget.onLongPressLink?.call(LinkPressPayload(
      url: url,
      text: data['text'] as String?,
      sourcePage: data['sourcePage'] as String? ?? '',
      extraction: _extract(url),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final injectJs = _injectJs;
    if (injectJs == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final windowId = widget.tab.windowId;

    return InAppWebView(
      windowId: windowId,
      initialUrlRequest: windowId == null
          ? URLRequest(url: WebUri(widget.tab.url))
          : null,
      initialSettings: buildWebViewSettings(isAndroid: isAndroid),
      initialUserScripts: UnmodifiableListView<UserScript>([
        UserScript(
          source: injectJs,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: true,
        ),
      ]),
      onWebViewCreated: (controller) {
        _controller = controller;
        controller.addJavaScriptHandler(
          handlerName: 'rl:longPress',
          callback: (args) {
            final map = args.isNotEmpty ? args.first : null;
            if (map is Map) {
              _handleLongPress(map);
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
        final url = action.request.url?.toString() ?? '';
        ref.read(browserProvider.notifier).openTab(
              url.isEmpty ? BrowserNotifier.blankUrl : url,
              windowId: action.windowId,
            );
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
