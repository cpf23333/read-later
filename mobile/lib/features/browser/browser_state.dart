/// 浏览器标签（不可变元数据）。
class BrowserTab {
  final String id;
  final String url;
  final String title;
  final String? favicon;
  final bool loading;
  final bool canGoBack;
  final bool canGoForward;

  /// 是否已经创建 WebView（懒加载：未激活的恢复标签先不加载）。
  final bool loaded;

  /// 最近使用序号（用于标签上限时的 LRU 淘汰）。
  final int lastUsedAt;

  /// 由 window.open / target=_blank 创建的窗口 id。
  final int? windowId;

  const BrowserTab({
    required this.id,
    required this.url,
    this.title = '',
    this.favicon,
    this.loading = false,
    this.canGoBack = false,
    this.canGoForward = false,
    this.loaded = false,
    this.lastUsedAt = 0,
    this.windowId,
  });

  BrowserTab copyWith({
    String? url,
    String? title,
    String? favicon,
    bool? loading,
    bool? canGoBack,
    bool? canGoForward,
    bool? loaded,
    int? lastUsedAt,
  }) {
    return BrowserTab(
      id: id,
      url: url ?? this.url,
      title: title ?? this.title,
      favicon: favicon ?? this.favicon,
      loading: loading ?? this.loading,
      canGoBack: canGoBack ?? this.canGoBack,
      canGoForward: canGoForward ?? this.canGoForward,
      loaded: loaded ?? this.loaded,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      windowId: windowId,
    );
  }
}

/// 浏览器状态。
class BrowserState {
  final List<BrowserTab> tabs;
  final String? activeTabId;

  const BrowserState({required this.tabs, this.activeTabId});

  BrowserTab? get activeTab {
    for (final tab in tabs) {
      if (tab.id == activeTabId) return tab;
    }
    return null;
  }

  BrowserState copyWith({List<BrowserTab>? tabs, String? activeTabId}) {
    return BrowserState(
      tabs: tabs ?? this.tabs,
      activeTabId: activeTabId ?? this.activeTabId,
    );
  }
}
