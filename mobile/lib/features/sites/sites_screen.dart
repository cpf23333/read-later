import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/site.dart';
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
      await ref.read(sitesProvider.notifier).deleteSite(id);
    }
  }

  Future<void> _showSiteActions(Site site) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.desktop_windows_outlined),
              title: const Text('User-Agent 设置'),
              subtitle: Text(_uaLabel(site)),
              onTap: () => Navigator.pop(sheetContext, 'ua'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除站点'),
              onTap: () => Navigator.pop(sheetContext, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'delete') {
      await _confirmDelete(site.id);
    } else if (action == 'ua') {
      await _editUserAgent(site);
    }
  }

  String _uaLabel(Site site) {
    switch (site.userAgentMode) {
      case 'desktop':
        return '桌面版';
      case 'custom':
        return '自定义';
      default:
        return '默认';
    }
  }

  Future<void> _editUserAgent(Site site) async {
    final result = await showDialog<_UserAgentResult>(
      context: context,
      builder: (dialogContext) => _UserAgentDialog(site: site),
    );
    if (result == null) return;

    try {
      await ref
          .read(sitesProvider.notifier)
          .updateUserAgent(
            site,
            mode: result.mode,
            userAgent: result.mode == 'custom' ? result.customUserAgent : null,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '已更新 ${site.title.isEmpty ? site.url : site.title} 的 User-Agent',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
      }
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
                onLongPress: () => _showSiteActions(site),
              );
            },
          );
        },
      ),
    );
  }
}

class _UserAgentResult {
  final String mode;
  final String? customUserAgent;

  const _UserAgentResult({required this.mode, this.customUserAgent});
}

class _UserAgentDialog extends StatefulWidget {
  const _UserAgentDialog({required this.site});

  final Site site;

  @override
  State<_UserAgentDialog> createState() => _UserAgentDialogState();
}

class _UserAgentDialogState extends State<_UserAgentDialog> {
  late String _mode;
  late final TextEditingController _customController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _mode = widget.site.userAgentMode;
    _customController = TextEditingController(
      text: widget.site.userAgent ?? '',
    );
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _save() {
    final custom = _customController.text.trim();
    if (_mode == 'custom' && custom.isEmpty) {
      setState(() => _error = '请输入自定义 User-Agent');
      return;
    }
    Navigator.pop(
      context,
      _UserAgentResult(
        mode: _mode,
        customUserAgent: _mode == 'custom' ? custom : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('User-Agent 设置'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.site.title.isEmpty ? widget.site.url : widget.site.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _mode,
              decoration: const InputDecoration(
                labelText: '模式',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'default', child: Text('默认（手机 UA）')),
                DropdownMenuItem(
                  value: 'desktop',
                  child: Text('桌面版（Windows Chrome）'),
                ),
                DropdownMenuItem(value: 'custom', child: Text('自定义')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _mode = value;
                  _error = null;
                });
              },
            ),
            if (_mode == 'custom') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _customController,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'User-Agent',
                  errorText: _error,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}
