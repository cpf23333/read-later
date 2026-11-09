import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/link.dart';
import '../../core/models/domain_stat.dart';
import '../../providers.dart';
import 'library_notifier.dart';
import 'link_card.dart';
import 'trash_screen.dart';

/// 收藏库：搜索、排序、网格/列表、分页、删除。
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _grid = true;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(libraryProvider.notifier).refresh());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSelect(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  void _clearSelection() {
    setState(_selected.clear);
  }

  Future<void> _confirmBatchDelete() async {
    if (_selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('把选中的 ${_selected.length} 条链接移入回收站？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ids = _selected.toList();
    _clearSelection();
    await ref.read(libraryProvider.notifier).batchDelete(ids);
  }

  void _openLink(LinkItem link) {
    if (_selected.isNotEmpty) {
      _toggleSelect(link.id);
      return;
    }
    ref.read(browserProvider.notifier).openTab(link.url);
    context.go('/browser');
  }

  Future<void> _showDomainFilter() async {
    List<DomainStat> domains;
    try {
      domains = await ref.read(apiClientProvider).listDomains();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载域名失败：$error')),
      );
      return;
    }
    if (!mounted) return;

    final current = ref.read(libraryProvider).domain;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: const Text('全部域名'),
              trailing: current == null ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(sheetContext, ''),
            ),
            for (final item in domains)
              ListTile(
                title: Text(item.domain),
                subtitle: Text('${item.count} 条'),
                trailing: current == item.domain ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(sheetContext, item.domain),
              ),
          ],
        ),
      ),
    );

    if (selected == null || !mounted) return;
    ref.read(libraryProvider.notifier).setDomain(selected.isEmpty ? null : selected);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(libraryProvider);
    final selecting = _selected.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        leading: selecting
            ? IconButton(
                tooltip: '取消选择',
                icon: const Icon(Icons.close),
                onPressed: _clearSelection,
              )
            : null,
        title: Text(selecting ? '已选 ${_selected.length}' : '收藏库'),
        actions: selecting
            ? [
                IconButton(
                  tooltip: '批量删除',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _confirmBatchDelete,
                ),
              ]
            : [
                IconButton(
                  tooltip: '按域名筛选',
                  icon: Badge(
                    isLabelVisible: state.domain != null,
                    child: const Icon(Icons.filter_alt_outlined),
                  ),
                  onPressed: _showDomainFilter,
                ),
                PopupMenuButton<String>(
                  tooltip: '排序',
                  icon: const Icon(Icons.sort),
                  onSelected: (value) {
                    switch (value) {
                      case 'created_desc':
                        ref.read(libraryProvider.notifier).setSort(sortBy: 'created_at', sortDesc: true);
                      case 'created_asc':
                        ref.read(libraryProvider.notifier).setSort(sortBy: 'created_at', sortDesc: false);
                      case 'title_asc':
                        ref.read(libraryProvider.notifier).setSort(sortBy: 'title', sortDesc: false);
                      case 'title_desc':
                        ref.read(libraryProvider.notifier).setSort(sortBy: 'title', sortDesc: true);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'created_desc', child: Text('最新收藏')),
                    PopupMenuItem(value: 'created_asc', child: Text('最早收藏')),
                    PopupMenuItem(value: 'title_asc', child: Text('标题 A→Z')),
                    PopupMenuItem(value: 'title_desc', child: Text('标题 Z→A')),
                  ],
                ),
                IconButton(
                  tooltip: _grid ? '列表视图' : '网格视图',
                  icon: Icon(_grid ? Icons.view_list : Icons.grid_view),
                  onPressed: () => setState(() => _grid = !_grid),
                ),
                IconButton(
                  tooltip: '回收站',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (routeContext) => const TrashScreen()),
                    );
                  },
                ),
              ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                hintText: '搜索标题或 URL',
              ),
              onChanged: (value) => ref.read(libraryProvider.notifier).setSearch(value),
            ),
          ),
          if (state.domain != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Row(
                children: [
                  InputChip(
                    label: Text(state.domain!),
                    onDeleted: () => ref.read(libraryProvider.notifier).setDomain(null),
                  ),
                  const Spacer(),
                  Text('${state.total} 条', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          Expanded(child: _buildBody(state)),
        ],
      ),
    );
  }

  Widget _buildBody(LibraryState state) {
    if (state.loading && state.links.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.links.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('加载失败：${state.error}'),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => ref.read(libraryProvider.notifier).refresh(),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (state.links.isEmpty) {
      return const Center(child: Text('还没有收藏，去浏览器长按链接试试'));
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 200) {
          ref.read(libraryProvider.notifier).loadMore();
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: () => ref.read(libraryProvider.notifier).refresh(),
        child: _grid ? _buildGrid(state) : _buildList(state),
      ),
    );
  }

  Widget _buildGrid(LibraryState state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000 ? 3 : 2;
        return GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: 2.6,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: state.links.length,
          itemBuilder: (context, index) {
            final link = state.links[index];
            return LinkCard(
              link: link,
              selected: _selected.contains(link.id),
              onTap: () => _openLink(link),
              onLongPress: () => _toggleSelect(link.id),
            );
          },
        );
      },
    );
  }

  Widget _buildList(LibraryState state) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: state.links.length,
      itemBuilder: (context, index) {
        final link = state.links[index];
        return LinkCard(
          link: link,
          selected: _selected.contains(link.id),
          onTap: () => _openLink(link),
          onLongPress: () => _toggleSelect(link.id),
        );
      },
    );
  }
}
