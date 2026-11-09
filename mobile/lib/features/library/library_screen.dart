import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/link.dart';
import '../../providers.dart';
import 'library_notifier.dart';
import 'link_card.dart';

/// 收藏库：搜索、排序、网格/列表、分页、删除。
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _grid = true;

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

  Future<void> _confirmDelete(LinkItem link) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除收藏'),
        content: Text('把「${link.title.isEmpty ? link.url : link.title}」移入回收站？'),
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
    if (confirmed == true) {
      await ref.read(libraryProvider.notifier).deleteLink(link.id);
    }
  }

  void _openLink(LinkItem link) {
    ref.read(browserProvider.notifier).openTab(link.url);
    context.go('/browser');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(libraryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('收藏库'),
        actions: [
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
              onTap: () => _openLink(link),
              onLongPress: () => _confirmDelete(link),
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
          onTap: () => _openLink(link),
          onLongPress: () => _confirmDelete(link),
        );
      },
    );
  }
}
