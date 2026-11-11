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
import 'global_user_agent.dart';

/// 长按链接回调数据（页面内提取延迟到保存时执行）。
class LinkPressPayload {
  final String url;
  final String? text;
  final String sourcePage;
  final Future<Map<String, dynamic>> Function()? extraction;

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
    this.onPageChanged,
    this.active = true,
  });

  final BrowserTab tab;
  final void Function(InAppWebViewController controller) onCreated;
  final void Function(LinkPressPayload payload)? onLongPressLink;
  final void Function(DetectedMedia media)? onMediaDetected;
  final void Function(String url)? onPageChanged;
  final bool active;

  @override
  ConsumerState<TabWebView> createState() => _TabWebViewState();
}

class _TabWebViewState extends ConsumerState<TabWebView> {
  String? _injectJs;
  InAppWebViewController? _controller;
  Completer<Map<String, dynamic>>? _extractCompleter;
  DateTime? _lastExternalBlockedAt;
  String? _appliedUserAgent;
  String? _lastPageUrl;
  bool _applyingUserAgent = false;

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
      await controller.evaluateJavascript(
        source: '''
        (() => {
          document.querySelectorAll('video, audio').forEach((el) => {
            try { el.pause(); } catch (_) {}
          });
        })();
      ''',
      );
    } catch (_) {
      // 页面已销毁等情况忽略。
    }
  }

  Future<void> _applyUserAgentForUrl(
    InAppWebViewController controller,
    String url,
  ) async {
    final sitesState = ref.read(sitesProvider);
    final globalState = ref.read(globalUserAgentProvider);
    final desired = resolveUserAgentForUrl(
      url,
      sitesState.sites,
      globalState.rule,
    );
    if (desired == _appliedUserAgent || _applyingUserAgent) return;

    _appliedUserAgent = desired;
    _applyingUserAgent = true;
    try {
      await controller.setSettings(
        settings: buildWebViewSettings(
          isAndroid: defaultTargetPlatform == TargetPlatform.android,
          userAgent: desired,
        ),
      );
      await controller.reload();
    } catch (_) {
      // 页面已销毁或 WebView 正在切换时忽略。
    } finally {
      _applyingUserAgent = false;
    }
  }

  Future<void> _applyUserAgentForCurrentPage() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      final current = await controller.getUrl();
      final url = current?.toString() ?? widget.tab.url;
      await _applyUserAgentForUrl(controller, url);
    } catch (_) {
      // 页面尚未就绪时忽略。
    }
  }

  /// 自动跳转拉起应用时提示拦截（3 秒内只提示一次，避免循环重定向刷屏）。
  void _notifyExternalBlocked() {
    final now = DateTime.now();
    final last = _lastExternalBlockedAt;
    if (last != null && now.difference(last) < const Duration(seconds: 3)) {
      return;
    }
    _lastExternalBlockedAt = now;
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已拦截网页自动打开外部应用')));
  }

  void _showLaunchFailed() {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('未找到可打开的应用')));
  }

  void _update({
    String? url,
    String? title,
    bool? loading,
    bool? canGoBack,
    bool? canGoForward,
  }) {
    ref
        .read(browserProvider.notifier)
        .updateTab(
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

    // 不立即执行页面提取，保存时再调用 callback。
    widget.onLongPressLink?.call(
      LinkPressPayload(
        url: url,
        text: data['text'] as String?,
        sourcePage: data['sourcePage'] as String? ?? '',
        extraction: () => _extract(url),
      ),
    );
  }

  void _notifyPageChanged(String url) {
    if (url.isEmpty || url == _lastPageUrl) return;
    _lastPageUrl = url;
    widget.onPageChanged?.call(url);
  }

  Future<void> _handleDetectedMedia(Map<String, dynamic> map) async {
    var media = DetectedMedia.fromMap(map);
    if (media.hasDash && media.sourcePage.isNotEmpty) {
      try {
        final cookies = await CookieManager.instance().getCookies(
          url: WebUri(media.sourcePage),
        );
        final cookie = cookies
            .map((item) => '${item.name}=${item.value}')
            .join('; ');
        if (cookie.isNotEmpty) media = media.copyWith(cookie: cookie);
      } catch (_) {
        // Cookie 读取失败时仍然播放公开/预览内容。
      }
    }
    if (!mounted) return;
    widget.onMediaDetected?.call(media);
  }

  @override
  Widget build(BuildContext context) {
    final injectJs = _injectJs;
    if (injectJs == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final windowId = widget.tab.windowId;
    final sitesState = ref.watch(sitesProvider);
    final globalState = ref.watch(globalUserAgentProvider);
    final sites = sitesState.sites;

    // 站点/全局 UA 规则未加载完成前先不创建 WebView，避免先按移动 UA 加载再刷新。
    if (!sitesState.initialized || !globalState.initialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final initialUserAgent = resolveUserAgentForUrl(
      widget.tab.url,
      sites,
      globalState.rule,
    );

    ref.listen(sitesProvider, (previous, next) {
      if (previous?.sites != next.sites) {
        unawaited(_applyUserAgentForCurrentPage());
      }
    });
    ref.listen(globalUserAgentProvider, (previous, next) {
      if (previous?.rule != next.rule) {
        unawaited(_applyUserAgentForCurrentPage());
      }
    });

    return InAppWebView(
      windowId: windowId,
      initialUrlRequest: windowId == null
          ? URLRequest(
              url: WebUri(widget.tab.url),
              // Android WebView 对初始请求的 UA 以 URLRequest header 为准；
              // 同时保留 initialSettings.userAgent 作为后续导航兜底。
              headers: initialUserAgent == null
                  ? null
                  : {'User-Agent': initialUserAgent},
            )
          : null,
      initialSettings: buildWebViewSettings(
        isAndroid: isAndroid,
        userAgent: initialUserAgent,
      ),
      initialUserScripts: UnmodifiableListView<UserScript>([
        UserScript(
          source: injectJs,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: true,
        ),
      ]),
      onWebViewCreated: (controller) {
        _controller = controller;
        _appliedUserAgent = initialUserAgent;
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
              unawaited(_handleDetectedMedia(Map<String, dynamic>.from(map)));
            }
            return null;
          },
        );
        controller.addJavaScriptHandler(
          handlerName: 'rl:dash',
          callback: (args) {
            final map = args.isNotEmpty ? args.first : null;
            if (map is Map) {
              unawaited(_handleDetectedMedia(Map<String, dynamic>.from(map)));
            }
            return null;
          },
        );
        controller.addJavaScriptHandler(
          handlerName: 'rl:urlChanged',
          callback: (args) {
            final map = args.isNotEmpty ? args.first : null;
            if (map is Map) {
              final url = map['url'];
              if (url is String) widget.onPageChanged?.call(url);
            }
            return null;
          },
        );
        widget.onCreated(controller);
      },
      onLoadStart: (controller, url) {
        _update(loading: true, url: url?.toString());
        if (url != null) _notifyPageChanged(url.toString());
        unawaited(
          _applyUserAgentForUrl(controller, url?.toString() ?? widget.tab.url),
        );
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
        if (url != null) _notifyPageChanged(url.toString());
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
        ref
            .read(browserProvider.notifier)
            .openTab(
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('暂不支持下载')));
      },
    );
  }
}
