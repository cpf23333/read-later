import 'package:flutter/material.dart';

import 'browser_state.dart';

/// 宽屏横向标签条。
class TabStrip extends StatelessWidget {
  const TabStrip({
    super.key,
    required this.tabs,
    required this.activeId,
    required this.onSelect,
    required this.onClose,
    required this.onNewTab,
  });

  final List<BrowserTab> tabs;
  final String? activeId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;
  final VoidCallback onNewTab;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: tabs.length,
              separatorBuilder: (context, index) => const SizedBox(width: 4),
              itemBuilder: (context, index) {
                final tab = tabs[index];
                final active = tab.id == activeId;
                final label = tab.title.isNotEmpty
                    ? tab.title
                    : (tab.url.isEmpty || tab.url == 'about:blank'
                          ? '新标签页'
                          : tab.url);
                return InkWell(
                  onTap: () => onSelect(tab.id),
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 120,
                      maxWidth: 220,
                    ),
                    padding: const EdgeInsets.only(left: 12, right: 4),
                    decoration: BoxDecoration(
                      color: active
                          ? colorScheme.secondaryContainer
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: active
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        IconButton(
                          iconSize: 16,
                          tooltip: '关闭标签',
                          icon: const Icon(Icons.close),
                          onPressed: () => onClose(tab.id),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            tooltip: '新标签',
            icon: const Icon(Icons.add),
            onPressed: onNewTab,
          ),
        ],
      ),
    );
  }
}
