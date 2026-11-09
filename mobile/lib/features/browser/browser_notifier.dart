import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/session_store.dart';
import '../../providers.dart';
import 'browser_state.dart';

/// 多标签状态管理：标签元数据、激活、关闭、LRU 淘汰、会话持久化。
class BrowserNotifier extends Notifier<BrowserState> {
  static const int maxTabs = 10;
  static const String blankUrl = 'about:blank';
  static const Duration persistDelay = Duration(milliseconds: 300);

  int _counter = 0;
  int _tick = 0;
  Timer? _persistTimer;

  int _nextTick() => ++_tick;

  @override
  BrowserState build() {
    ref.onDispose(() => _persistTimer?.cancel());
    final first = _createTab(blankUrl, loaded: true, activate: true);
    return BrowserState(tabs: [first], activeTabId: first.id);
  }

  BrowserTab _createTab(
    String url, {
    int? windowId,
    bool loaded = false,
    bool activate = false,
  }) {
    return BrowserTab(
      id: 'tab_${DateTime.now().microsecondsSinceEpoch}_${_counter++}',
      url: url,
      loaded: loaded,
      lastUsedAt: _nextTick(),
      windowId: windowId,
    );
  }

  void openTab(String url, {bool activate = true, int? windowId}) {
    final trimmed = url.trim();
    if (trimmed.isEmpty && windowId == null) return;

    var tabs = List<BrowserTab>.from(state.tabs);
    if (tabs.length >= maxTabs) {
      final inactive = tabs.where((t) => t.id != state.activeTabId).toList()
        ..sort((a, b) => a.lastUsedAt.compareTo(b.lastUsedAt));
      if (inactive.isNotEmpty) {
        tabs.remove(inactive.first);
      }
    }

    final tab = _createTab(
      trimmed.isEmpty ? blankUrl : trimmed,
      windowId: windowId,
      loaded: activate,
      activate: activate,
    );
    tabs.add(tab);

    state = BrowserState(
      tabs: tabs,
      activeTabId: activate ? tab.id : state.activeTabId,
    );
    _schedulePersist();
  }

  void closeTab(String id) {
    final tabs = List<BrowserTab>.from(state.tabs)..removeWhere((t) => t.id == id);
    if (tabs.isEmpty) {
      final blank = _createTab(blankUrl, loaded: true, activate: true);
      tabs.add(blank);
      state = BrowserState(tabs: tabs, activeTabId: blank.id);
    } else {
      final active = state.activeTabId == id ? tabs.last.id : state.activeTabId;
      state = BrowserState(tabs: tabs, activeTabId: active);
    }
    _schedulePersist();
  }

  void activate(String id) {
    final now = _nextTick();
    final tabs = [
      for (final tab in state.tabs)
        if (tab.id == id)
          tab.copyWith(loaded: true, lastUsedAt: now)
        else
          tab,
    ];
    if (!tabs.any((t) => t.id == id)) return;
    state = BrowserState(tabs: tabs, activeTabId: id);
    _schedulePersist();
  }

  void updateTab(
    String id, {
    String? url,
    String? title,
    String? favicon,
    bool? loading,
    bool? canGoBack,
    bool? canGoForward,
  }) {
    final tabs = [
      for (final tab in state.tabs)
        if (tab.id == id)
          tab.copyWith(
            url: url,
            title: title,
            favicon: favicon,
            loading: loading,
            canGoBack: canGoBack,
            canGoForward: canGoForward,
          )
        else
          tab,
    ];
    state = BrowserState(tabs: tabs, activeTabId: state.activeTabId);
    _schedulePersist();
  }

  /// 从上次会话恢复（只恢复 URL 列表，非活动标签在首次激活时加载）。
  /// 若用户已经打开了新标签（例如从收藏库点开链接），不覆盖当前标签。
  void initialize(List<String> urls, String? activeUrl) {
    final nonEmpty = urls.where((u) => u.isNotEmpty).toList();
    if (nonEmpty.isEmpty) return;
    if (state.tabs.length != 1 || state.tabs.single.url != blankUrl) return;

    final tabs = <BrowserTab>[];
    BrowserTab? activeTab;
    for (final url in nonEmpty) {
      final isActive = url == activeUrl || (activeUrl == null && tabs.isEmpty);
      final tab = _createTab(url, loaded: isActive, activate: isActive);
      tabs.add(tab);
      if (isActive) activeTab ??= tab;
    }
    activeTab ??= tabs.first;

    state = BrowserState(tabs: tabs, activeTabId: activeTab.id);
    _schedulePersist();
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(persistDelay, () {
      final store = ref.read(sessionStoreProvider);
      final data = SessionData(
        urls: state.tabs.map((t) => t.url).toList(),
        activeUrl: state.activeTab?.url,
      );
      store.save(data);
    });
  }
}
