import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../providers.dart';
import 'browser_notifier.dart';
import 'browser_toolbar.dart';
import 'tab_strip.dart';
import 'tab_webview.dart';

/// 内置浏览器主界面：多标签 + 工具栏 + WebView 栈。
class BrowserScreen extends ConsumerStatefulWidget {
  const BrowserScreen({super.key});

  @override
  ConsumerState<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends ConsumerState<BrowserScreen> {
  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final data = await ref.read(sessionStoreProvider).load();
    if (!mounted || data == null) return;
    ref.read(browserProvider.notifier).initialize(data.urls, data.activeUrl);
  }

  InAppWebViewController? _activeController() {
    final active = ref.read(browserProvider).activeTab;
    if (active == null) return null;
    return ref.read(tabRegistryProvider).of(active.id);
  }

  void _navigate(String url) {
    final controller = _activeController();
    if (controller == null) {
      ref.read(browserProvider.notifier).openTab(url);
      return;
    }
    controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  Future<void> _handleBack() async {
    final notifier = ref.read(browserProvider.notifier);
    final active = ref.read(browserProvider).activeTab;
    if (active == null) return;

    final controller = _activeController();
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
      return;
    }

    if (ref.read(browserProvider).tabs.length > 1) {
      notifier.closeTab(active.id);
      return;
    }
    await SystemNavigator.pop();
  }

  void _showTabMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('新标签页'),
              onTap: () {
                Navigator.pop(sheetContext);
                ref.read(browserProvider.notifier).openTab(BrowserNotifier.blankUrl);
              },
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('关闭当前标签'),
              onTap: () {
                final active = ref.read(browserProvider).activeTab;
                Navigator.pop(sheetContext);
                if (active != null) {
                  ref.read(browserProvider.notifier).closeTab(active.id);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(browserProvider);
    final active = state.activeTab;
    final registry = ref.watch(tabRegistryProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              BrowserToolbar(
                url: active?.url == BrowserNotifier.blankUrl ? '' : (active?.url ?? ''),
                canGoBack: active?.canGoBack ?? false,
                canGoForward: active?.canGoForward ?? false,
                loading: active?.loading ?? false,
                onNavigate: _navigate,
                onBack: () => _activeController()?.goBack(),
                onForward: () => _activeController()?.goForward(),
                onReload: () => _activeController()?.reload(),
                onStop: () => _activeController()?.stopLoading(),
                onCollectPage: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('收藏当前页：稍后接入')),
                  );
                },
                onMenu: _showTabMenu,
              ),
              TabStrip(
                tabs: state.tabs,
                activeId: state.activeTabId,
                onSelect: (id) => ref.read(browserProvider.notifier).activate(id),
                onClose: (id) => ref.read(browserProvider.notifier).closeTab(id),
                onNewTab: () => ref.read(browserProvider.notifier).openTab(BrowserNotifier.blankUrl),
              ),
              const Divider(height: 1),
              Expanded(
                child: Stack(
                  children: [
                    for (final tab in state.tabs)
                      Offstage(
                        offstage: tab.id != state.activeTabId,
                        child: TabWebView(
                          key: ValueKey(tab.id),
                          tab: tab,
                          onCreated: (controller) => registry.register(tab.id, controller),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
