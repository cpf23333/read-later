import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/site.dart';
import '../../core/web/title_resolver.dart';
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
              title: const Text('编辑站点'),
              subtitle: Text(_uaLabel(site)),
              onTap: () => Navigator.pop(sheetContext, 'edit'),
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
    } else if (action == 'edit') {
      await _editSite(site);
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

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editSite(Site site) async {
    final result = await showDialog<_SiteEditResult>(
      context: context,
      builder: (dialogContext) => _SiteEditDialog(
        site: site,
        resolveMeta: (url) => ref.read(titleResolverProvider).resolve(url),
        prepareIcon: (url) => ref.read(siteServiceProvider).prepareIcon(url),
        uploadIcon: (bytes, filename) =>
            ref.read(siteServiceProvider).uploadIconBytes(bytes, filename),
      ),
    );
    if (result == null) return;

    final oldTitle = site.title;
    final oldIcon = site.iconUrl;

    try {
      await ref
          .read(sitesProvider.notifier)
          .updateSite(
            site,
            title: result.title,
            iconUrl: result.iconUrl,
            mode: result.mode,
            userAgent: result.mode == 'custom' ? result.customUserAgent : null,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已更新 ${site.title.isEmpty ? site.url : site.title}'),
            action: SnackBarAction(
              label: '撤回',
              onPressed: () => _showUndoDialog(
                site,
                oldTitle,
                oldIcon,
                result.title != oldTitle,
                result.iconUrl != oldIcon,
              ),
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

  Future<void> _showUndoDialog(
    Site site,
    String oldTitle,
    String? oldIcon,
    bool titleChanged,
    bool iconChanged,
  ) async {
    if (!titleChanged && !iconChanged) return;

    var undoTitle = titleChanged;
    var undoIcon = iconChanged;
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('撤回哪些修改？'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (titleChanged)
                CheckboxListTile(
                  value: undoTitle,
                  title: const Text('标题'),
                  onChanged: (value) =>
                      setDialogState(() => undoTitle = value ?? false),
                ),
              if (iconChanged)
                CheckboxListTile(
                  value: undoIcon,
                  title: const Text('图标'),
                  onChanged: (value) =>
                      setDialogState(() => undoIcon = value ?? false),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, <String>{
                  if (undoTitle) 'title',
                  if (undoIcon) 'icon',
                });
              },
              child: const Text('撤回'),
            ),
          ],
        ),
      ),
    );
    if (selected == null || selected.isEmpty) return;

    final matches = ref
        .read(sitesProvider)
        .sites
        .where((item) => item.id == site.id);
    final current = matches.isEmpty ? site : matches.first;
    try {
      await ref
          .read(sitesProvider.notifier)
          .updateSite(
            current,
            title: selected.contains('title') ? oldTitle : current.title,
            iconUrl: selected.contains('icon') ? oldIcon : current.iconUrl,
            mode: current.userAgentMode,
            userAgent: current.userAgent,
          );
      if (mounted) _snack('已撤回所选修改');
    } catch (error) {
      if (mounted) _snack('撤回失败：$error');
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

class _SiteEditResult {
  final String title;
  final String? iconUrl;
  final String mode;
  final String? customUserAgent;

  const _SiteEditResult({
    required this.title,
    required this.iconUrl,
    required this.mode,
    this.customUserAgent,
  });
}

class _SiteEditDialog extends StatefulWidget {
  const _SiteEditDialog({
    required this.site,
    required this.resolveMeta,
    required this.prepareIcon,
    required this.uploadIcon,
  });

  final Site site;
  final Future<PageMeta> Function(String url) resolveMeta;
  final Future<String?> Function(String? url) prepareIcon;
  final Future<String?> Function(Uint8List bytes, String filename) uploadIcon;

  @override
  State<_SiteEditDialog> createState() => _SiteEditDialogState();
}

class _SiteEditDialogState extends State<_SiteEditDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _customController;
  late String _mode;
  String? _error;
  late String _originalTitle;
  late String? _originalIcon;
  String? _iconUrl;
  bool _detecting = false;
  bool _uploadingIcon = false;
  bool _titleDetected = false;
  bool _iconDetected = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.site.title);
    _customController = TextEditingController(
      text: widget.site.userAgent ?? '',
    );
    _mode = widget.site.userAgentMode;
    _originalTitle = widget.site.title;
    _originalIcon = widget.site.iconUrl;
    _iconUrl = widget.site.iconUrl;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _customController.dispose();
    super.dispose();
  }

  Future<void> _detect() async {
    if (_detecting) return;
    setState(() => _detecting = true);
    try {
      final meta = await widget.resolveMeta(widget.site.url);
      if (!mounted) return;
      var titleChanged = false;
      var iconChanged = false;
      final title = (meta.title ?? '').trim();
      if (title.isNotEmpty && title != _titleController.text) {
        _titleController.text = title;
        titleChanged = true;
      }
      final iconSource = (meta.iconUrl ?? '').trim().isNotEmpty
          ? meta.iconUrl!.trim()
          : '${widget.site.url}/favicon.ico';
      final uploaded = await widget.prepareIcon(iconSource);
      if (uploaded != null && uploaded != _iconUrl) {
        _iconUrl = uploaded;
        iconChanged = true;
      }
      setState(() {
        _detecting = false;
        _titleDetected = titleChanged;
        _iconDetected = iconChanged;
      });
      if (!titleChanged && !iconChanged) _snack('没有探测到新的标题或图标');
    } catch (error) {
      if (!mounted) return;
      setState(() => _detecting = false);
      _snack('探测失败：$error');
    }
  }

  Future<void> _pickIcon() async {
    if (_uploadingIcon) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() => _uploadingIcon = true);
    try {
      final bytes = await picked.readAsBytes();
      final url = await widget.uploadIcon(bytes, picked.name);
      if (!mounted) return;
      setState(() {
        _uploadingIcon = false;
        _iconUrl = url;
        _iconDetected = url != null && url != _originalIcon;
      });
      if (url == null) _snack('图标上传失败');
    } catch (error) {
      if (!mounted) return;
      setState(() => _uploadingIcon = false);
      _snack('图标上传失败：$error');
    }
  }

  void _restoreTitle() {
    setState(() {
      _titleController.text = _originalTitle;
      _titleDetected = false;
    });
  }

  void _restoreIcon() {
    setState(() {
      _iconUrl = _originalIcon;
      _iconDetected = false;
    });
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _save() {
    final custom = _customController.text.trim();
    if (_mode == 'custom' && custom.isEmpty) {
      setState(() => _error = '请输入自定义 User-Agent');
      return;
    }
    Navigator.pop(
      context,
      _SiteEditResult(
        title: _titleController.text.trim(),
        iconUrl: _iconUrl,
        mode: _mode,
        customUserAgent: _mode == 'custom' ? custom : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑站点'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.site.url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _detecting ? null : _detect,
                  icon: _detecting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: const Text('重新探测'),
                ),
                if (_titleDetected)
                  TextButton(
                    onPressed: _restoreTitle,
                    child: const Text('恢复标题'),
                  ),
                if (_iconDetected)
                  TextButton(
                    onPressed: _restoreIcon,
                    child: const Text('恢复图标'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: '标题',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IconPreview(url: _iconUrl ?? ''),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _uploadingIcon ? null : _pickIcon,
                        icon: _uploadingIcon
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.upload_outlined),
                        label: const Text('上传图标'),
                      ),
                      if (_iconUrl != null)
                        TextButton(
                          onPressed: () => setState(() {
                            _iconUrl = null;
                            _iconDetected = true;
                          }),
                          child: const Text('移除图标'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _mode,
              decoration: const InputDecoration(
                labelText: 'User-Agent',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'default', child: Text('跟随全局默认')),
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

class _IconPreview extends StatelessWidget {
  const _IconPreview({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (!url.startsWith('http')) {
      return _placeholder(context);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: url,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorWidget: (context, imageUrl, error) => _placeholder(context),
        placeholder: (context, imageUrl) => _placeholder(context),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.image_outlined,
        color: Theme.of(context).colorScheme.onSecondaryContainer,
      ),
    );
  }
}
