import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/link.dart';
import '../../core/models/site.dart';
import '../../core/util/origin.dart';
import '../../providers.dart';
import 'trash_notifier.dart';

/// 回收站：链接 / 站点两个 tab。
class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key});

  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<TrashScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    Future.microtask(() => ref.read(trashProvider.notifier).load());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<bool> _confirm(String title) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: const Text('此操作不可恢复，确定继续？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('确定')),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _restoreLink(TrashItem item) async {
    await ref.read(trashProvider.notifier).restoreLink(item.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已还原')));
    }
  }

  Future<void> _purgeLink(TrashItem item) async {
    if (!await _confirm('永久删除链接')) return;
    await ref.read(trashProvider.notifier).purgeLink(item.id);
  }

  Future<void> _restoreSite(Site site) async {
    await ref.read(trashProvider.notifier).restoreSite(site.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已还原站点')));
    }
  }

  Future<void> _purgeSite(Site site) async {
    if (!await _confirm('永久删除站点')) return;
    await ref.read(trashProvider.notifier).purgeSite(site.id);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(trashProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('回收站'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '链接'),
            Tab(text: '站点'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(trashProvider.notifier).load(),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLinks(state),
          _buildSites(state),
        ],
      ),
    );
  }

  Widget _buildLinks(TrashState state) {
    if (state.loading && state.links.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.links.isEmpty) {
      return const Center(child: Text('链接回收站是空的'));
    }

    return ListView.separated(
      itemCount: state.links.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = state.links[index];
        return ListTile(
          title: Text(item.title.isEmpty ? item.url : item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(hostOf(item.url) ?? item.url, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '还原',
                icon: const Icon(Icons.restore),
                onPressed: () => _restoreLink(item),
              ),
              IconButton(
                tooltip: '永久删除',
                icon: const Icon(Icons.delete_forever),
                onPressed: () => _purgeLink(item),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSites(TrashState state) {
    if (state.loading && state.sites.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.sites.isEmpty) {
      return const Center(child: Text('站点回收站是空的'));
    }

    return ListView.separated(
      itemCount: state.sites.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final site = state.sites[index];
        return ListTile(
          title: Text(site.title.isEmpty ? site.url : site.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(site.url, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '还原',
                icon: const Icon(Icons.restore),
                onPressed: () => _restoreSite(site),
              ),
              IconButton(
                tooltip: '永久删除',
                icon: const Icon(Icons.delete_forever),
                onPressed: () => _purgeSite(site),
              ),
            ],
          ),
        );
      },
    );
  }
}
