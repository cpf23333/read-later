import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/session_store.dart';
import '../../providers.dart';
import 'browser_state.dart';

/// 多标签状态管理：标签元数据、激活、关闭、会话持久化。
class BrowserNotifier extends Notifier<BrowserState> {
  static const int maxTabs = 10;
  static const String blankUrl = 'about:blank';
  static const Duration persistDelay = Duration(milliseconds: 300);

  int _counter = 0;
  Timer? _persistTimer;

  @override
  BrowserState build() {
    ref.onDispose(() => _persistTimer?.cancel());
    final first = _createTab(blankUrl);
    return BrowserState(tabs: [first], activeTabId: first.id);
  }

  BrowserTab _createTab(String url) {
    return BrowserTab(
      id: 'tab_${DateTime.now().microsecondsSinceEpoch}_${_counter++}',
      url: url,
    );
  }

  void openTab(String url, {bool activate = true}) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;

    var tabs = List<BrowserTab>.from(state.tabs);
    if (tabs.length >= maxTabs) {
      final removable = tabs.where((t) => t.id != state.activeTabId).toList();
      if (removable.isNotEmpty) {
        tabs.remove(removable.first);
      }
    }

    final tab = _createTab(trimmed);
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
      final blank = _createTab(blankUrl);
      tabs.add(blank);
      state = BrowserState(tabs: tabs, activeTabId: blank.id);
    } else {
      final active = state.activeTabId == id ? tabs.last.id : state.activeTabId;
      state = BrowserState(tabs: tabs, activeTabId: active);
    }
    _schedulePersist();
  }

  void activate(String id) {
    if (!state.tabs.any((t) => t.id == id)) return;
    state = state.copyWith(activeTabId: id);
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

  /// 从上次会话恢复（只恢复 URL 列表，页面在首次激活时加载）。
  void initialize(List<String> urls, String? activeUrl) {
    final nonEmpty = urls.where((u) => u.isNotEmpty).toList();
    if (nonEmpty.isEmpty) return;

    final tabs = nonEmpty.map(_createTab).toList();
    var activeId = tabs.first.id;
    if (activeUrl != null) {
      for (var i = 0; i < nonEmpty.length; i++) {
        if (nonEmpty[i] == activeUrl) {
          activeId = tabs[i].id;
          break;
        }
      }
    }
    state = BrowserState(tabs: tabs, activeTabId: activeId);
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
