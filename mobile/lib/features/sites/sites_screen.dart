import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers.dart';
import 'site_card.dart';
import 'sites_notifier.dart';

/// 站点页：收藏的网站（origin）网格。
class SitesScreen extends ConsumerStatefulWidget {
  const SitesScreen({super.key});

  @override
  ConsumerState<SitesScreen> createState() => _SitesScreenState();
}

class _SitesScreenState extends ConsumerState<SitesScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(sitesProvider.notifier).refresh());
  }

  Future<void> _confirmDelete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除站点'),
        content: const Text('站点会移入回收站，可稍后还原。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(sitesProvider.notifier).deleteSite(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sitesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('站点'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(sitesProvider.notifier).refresh(),
          ),
        ],
      ),
      body: _buildBody(state),
    );
  }

  Widget _buildBody(SitesState state) {
    if (state.loading && state.sites.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.sites.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('加载失败：${state.error}'),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => ref.read(sitesProvider.notifier).refresh(),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (state.sites.isEmpty) {
      return const Center(child: Text("在网页里长按链接，选择'收藏主站'"));
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(sitesProvider.notifier).refresh(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1000 ? 3 : 2;
          return GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              childAspectRatio: 3.2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: state.sites.length,
            itemBuilder: (context, index) {
              final site = state.sites[index];
              return SiteCard(
                site: site,
                onTap: () {
                  ref.read(browserProvider.notifier).openTab(site.url);
                  context.go('/browser');
                },
                onLongPress: () => _confirmDelete(site.id),
              );
            },
          );
        },
      ),
    );
  }
}
