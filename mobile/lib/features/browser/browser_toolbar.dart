import 'package:flutter/material.dart';

/// 把用户输入解析成可导航的 URL：
/// - 空输入返回空串；
/// - 含空格走 Bing 搜索；
/// - 无 scheme 补 https://。
String normalizeUserInput(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.contains(' ')) {
    return 'https://www.bing.com/search?q=${Uri.encodeComponent(trimmed)}';
  }
  if (!trimmed.contains('://')) {
    return 'https://$trimmed';
  }
  return trimmed;
}

/// 浏览器顶部工具栏：前进后退、地址栏、收藏、菜单。
class BrowserToolbar extends StatefulWidget {
  const BrowserToolbar({
    super.key,
    required this.url,
    required this.canGoBack,
    required this.canGoForward,
    required this.loading,
    required this.onNavigate,
    required this.onBack,
    required this.onForward,
    required this.onReload,
    required this.onStop,
    required this.onCollectPage,
    required this.onMenu,
  });

  final String url;
  final bool canGoBack;
  final bool canGoForward;
  final bool loading;
  final ValueChanged<String> onNavigate;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onReload;
  final VoidCallback onStop;
  final VoidCallback onCollectPage;
  final VoidCallback onMenu;

  @override
  State<BrowserToolbar> createState() => _BrowserToolbarState();
}

class _BrowserToolbarState extends State<BrowserToolbar> {
  late final TextEditingController _urlController;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.url);
  }

  @override
  void didUpdateWidget(covariant BrowserToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && widget.url != _urlController.text) {
      _urlController.text = widget.url;
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final resolved = normalizeUserInput(value);
    if (resolved.isEmpty) return;
    _focusNode.unfocus();
    widget.onNavigate(resolved);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: '后退',
            icon: const Icon(Icons.arrow_back),
            onPressed: widget.canGoBack ? widget.onBack : null,
          ),
          IconButton(
            tooltip: '前进',
            icon: const Icon(Icons.arrow_forward),
            onPressed: widget.canGoForward ? widget.onForward : null,
          ),
          IconButton(
            tooltip: widget.loading ? '停止' : '刷新',
            icon: Icon(widget.loading ? Icons.close : Icons.refresh),
            onPressed: widget.loading ? widget.onStop : widget.onReload,
          ),
          Expanded(
            child: TextField(
              controller: _urlController,
              focusNode: _focusNode,
              textInputAction: TextInputAction.go,
              onSubmitted: _submit,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                hintText: '输入网址或搜索',
              ),
            ),
          ),
          IconButton(
            tooltip: '收藏当前页',
            icon: const Icon(Icons.bookmark_add_outlined),
            onPressed: widget.onCollectPage,
          ),
          IconButton(
            tooltip: '标签',
            icon: const Icon(Icons.tab),
            onPressed: widget.onMenu,
          ),
        ],
      ),
    );
  }
}
