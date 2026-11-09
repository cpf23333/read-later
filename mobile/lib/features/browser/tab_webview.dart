import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/external_app_launcher.dart';
import '../../platform/system_ui.dart';
import '../../platform/webview_settings.dart';
import '../../providers.dart';
import 'browser_notifier.dart';
import 'browser_state.dart';
import 'detected_media.dart';
import 'external_navigation.dart';
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
    this.onMediaDetected,
    this.active = true,
  });

  final BrowserTab tab;
  final void Function(InAppWebViewController controller) onCreated;
  final void Function(LinkPressPayload payload)? onLongPressLink;
  final void Function(DetectedMedia media)? onMediaDetected;
  final bool active;

  @override
  ConsumerState<TabWebView> createState() => _TabWebViewState();
}

class _TabWebViewState extends ConsumerState<TabWebView> {
  String? _injectJs;
  InAppWebViewController? _controller;
  Completer<Map<String, dynamic>>? _extractCompleter;
  DateTime? _lastExternalBlockedAt;

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

  /// 自动跳转拉起应用时提示拦截（3 秒内只提示一次，避免循环重定向刷屏）。
  void _notifyExternalBlocked() {
    final now = DateTime.now();
    final last = _lastExternalBlockedAt;
    if (last != null && now.difference(last) < const Duration(seconds: 3)) return;
    _lastExternalBlockedAt = now;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已拦截网页自动打开外部应用')),
    );
  }

  void _showLaunchFailed() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('未找到可打开的应用')),
    );
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
        controller.addJavaScriptHandler(
          handlerName: 'rl:media',
          callback: (args) {
            final map = args.isNotEmpty ? args.first : null;
            if (map is Map) {
              widget.onMediaDetected?.call(
                DetectedMedia.fromMap(Map<String, dynamic>.from(map)),
              );
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
        final uri = Uri.tryParse(url);
        if (isExternalScheme(uri?.scheme)) {
          // target=_blank / window.open 指向外部 scheme：同样需要用户确认。
          if (!mounted) return false;
          final confirmed = await confirmExternalLaunch(
            context,
            url: url,
            scheme: uri!.scheme,
          );
          if (confirmed && mounted) {
            final launched = await launchExternalUrl(url);
            if (!launched && mounted) {
              _showLaunchFailed();
            }
          }
          return false;
        }
        ref.read(browserProvider.notifier).openTab(
              url.isEmpty ? BrowserNotifier.blankUrl : url,
              windowId: action.windowId,
            );
        return true;
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final url = navigationAction.request.url?.toString() ?? '';
        final scheme = Uri.tryParse(url)?.scheme;
        final kind = classifyNavigation(
          scheme: scheme,
          hasGesture: navigationAction.hasGesture ?? false,
        );

        if (kind == ExternalNavigationKind.internal) {
          return NavigationActionPolicy.ALLOW;
        }
        if (kind == ExternalNavigationKind.externalAutomatic) {
          // 页面脚本/重定向自动拉起应用：直接拦截，不弹窗。
          _notifyExternalBlocked();
          return NavigationActionPolicy.CANCEL;
        }

        if (!mounted) return NavigationActionPolicy.CANCEL;
        final confirmed = await confirmExternalLaunch(
          context,
          url: url,
          scheme: scheme!,
        );
        if (!confirmed) return NavigationActionPolicy.CANCEL;

        final launched = await launchExternalUrl(url);
        if (!launched && mounted) {
          _showLaunchFailed();
        }
        return NavigationActionPolicy.CANCEL;
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
