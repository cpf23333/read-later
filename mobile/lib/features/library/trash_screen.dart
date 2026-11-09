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
  final Set<String> _selectedLinks = {};

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

  void _toggleLink(String id) {
    setState(() {
      if (!_selectedLinks.add(id)) _selectedLinks.remove(id);
    });
  }

  void _clearSelection() {
    setState(_selectedLinks.clear);
  }

  Future<void> _batchRestore() async {
    final ids = _selectedLinks.toList();
    _clearSelection();
    await ref.read(trashProvider.notifier).batchRestoreLinks(ids);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已批量还原')));
    }
  }

  Future<void> _batchPurge() async {
    if (!await _confirm('批量永久删除链接')) return;
    final ids = _selectedLinks.toList();
    _clearSelection();
    await ref.read(trashProvider.notifier).batchPurgeLinks(ids);
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
        title: Text(
          _selectedLinks.isNotEmpty ? '已选 ${_selectedLinks.length}' : '回收站',
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '链接'),
            Tab(text: '站点'),
          ],
        ),
        actions: _selectedLinks.isNotEmpty
            ? [
                IconButton(
                  tooltip: '批量还原',
                  icon: const Icon(Icons.restore),
                  onPressed: _batchRestore,
                ),
                IconButton(
                  tooltip: '批量永久删除',
                  icon: const Icon(Icons.delete_forever),
                  onPressed: _batchPurge,
                ),
                IconButton(
                  tooltip: '取消选择',
                  icon: const Icon(Icons.close),
                  onPressed: _clearSelection,
                ),
              ]
            : [
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
        final selecting = _selectedLinks.isNotEmpty;
        final selected = _selectedLinks.contains(item.id);
        return ListTile(
          leading: selecting
              ? Checkbox(value: selected, onChanged: (value) => _toggleLink(item.id))
              : null,
          onTap: selecting ? () => _toggleLink(item.id) : null,
          onLongPress: () => _toggleLink(item.id),
          title: Text(item.title.isEmpty ? item.url : item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(hostOf(item.url) ?? item.url, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: selecting
              ? null
              : Row(
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
