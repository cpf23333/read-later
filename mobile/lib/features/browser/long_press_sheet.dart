import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/errors.dart';
import '../../core/util/origin.dart';
import '../../providers.dart';
import 'capture_service.dart';

/// 长按菜单保存结果。
class LongPressResult {
  final bool saved;
  final String kind; // 'link' | 'site'
  final bool droppedImage;
  final bool droppedScreenshot;

  const LongPressResult({
    required this.saved,
    required this.kind,
    this.droppedImage = false,
    this.droppedScreenshot = false,
  });

  bool get droppedAny => droppedImage || droppedScreenshot;
}

/// 长按链接弹出的收藏菜单（收藏固定第一项，收藏主站第二项）。
class LongPressSheet extends ConsumerStatefulWidget {
  const LongPressSheet({
    super.key,
    required this.url,
    required this.sourcePage,
    this.linkText,
    this.nearbyText,
    this.nearbyImage,
    this.extraction,
    required this.takeScreenshot,
    this.onOpenInNewTab,
  });

  final String url;
  final String sourcePage;
  final String? linkText;
  final String? nearbyText;
  final String? nearbyImage;
  final Future<Map<String, dynamic>>? extraction;
  final Future<String?> Function() takeScreenshot;
  final ValueChanged<String>? onOpenInNewTab;

  @override
  ConsumerState<LongPressSheet> createState() => _LongPressSheetState();
}

class _LongPressSheetState extends ConsumerState<LongPressSheet> {
  LinkPreview? _preview;
  Object? _error;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final previewFuture = ref.read(captureServiceProvider).prepare(
            url: widget.url,
            linkText: widget.linkText,
            nearbyText: widget.nearbyText,
            nearbyImage: widget.nearbyImage,
            sourcePage: widget.sourcePage,
          );
      final extractionFuture = widget.extraction ?? Future<Map<String, dynamic>>.value(const {});

      final preview = await previewFuture;
      final extracted = await extractionFuture;

      final firstNonEmpty = [
        preview.nearbyImage,
        extracted['nearbyImage'] as String?,
      ].firstWhere((value) => value != null && value.isNotEmpty, orElse: () => null);

      if (!mounted) return;
      setState(() {
        _preview = preview.copyWith(nearbyImage: firstNonEmpty);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _saveLink() async {
    final preview = _preview;
    if (preview == null || _saving) return;

    setState(() => _saving = true);
    String? screenshot;
    try {
      screenshot = await widget.takeScreenshot();
    } catch (_) {
      // 截图失败不阻塞收藏。
      screenshot = null;
    }

    final caps = applyMediaCaps(
      nearbyImage: preview.nearbyImage,
      screenshot: screenshot,
    );

    try {
      await ref.read(captureServiceProvider).save(
            preview.copyWith(nearbyImage: caps.nearbyImage),
            screenshotBase64: caps.screenshot,
          );
      if (!mounted) return;
      setState(() => _saving = false);
      Navigator.of(context).maybePop(LongPressResult(
        saved: true,
        kind: 'link',
        droppedImage: caps.droppedImage,
        droppedScreenshot: caps.droppedScreenshot,
      ));
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：${_message(error)}')),
      );
    }
  }

  Future<void> _saveSite() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final service = ref.read(siteServiceProvider);
      final draft = await service.prepare(widget.url);
      await service.save(draft);
      if (!mounted) return;
      setState(() => _saving = false);
      Navigator.of(context).maybePop(const LongPressResult(saved: true, kind: 'site'));
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('收藏主站失败：${_message(error)}')),
      );
    }
  }

  String _message(Object error) {
    if (error is ApiException) return error.message;
    return '$error';
  }

  bool get _notConfigured => _error is NotConfiguredException;

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (preview?.nearbyImage != null) ...[
                  _PreviewImage(value: preview!.nearbyImage!),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        preview?.title ?? (widget.linkText ?? widget.url),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                      if (preview?.existingTitle != null &&
                          preview!.existingTitle!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '已有收藏：${preview.existingTitle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 12),
                    Text('正在准备…'),
                  ],
                ),
              ),
            if (_notConfigured)
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('服务器未配置，去设置'),
                onTap: () {
                  Navigator.of(context).maybePop();
                  context.go('/settings');
                },
              ),
            if (_error != null && !_notConfigured)
              ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text('加载失败：${_message(_error!)}'),
                trailing: TextButton(onPressed: _load, child: const Text('重试')),
              ),
            ListTile(
              enabled: !_saving && !_loading && preview != null,
              leading: const Icon(Icons.bookmark_add_outlined),
              title: const Text('收藏到稍后再看'),
              onTap: _saveLink,
            ),
            ListTile(
              enabled: !_saving && !_loading,
              leading: const Icon(Icons.public_outlined),
              title: Text('收藏主站 ${hostOf(widget.url) ?? ''}'.trim()),
              onTap: _saveSite,
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('在新标签打开'),
              onTap: () {
                Navigator.of(context).maybePop();
                widget.onOpenInNewTab?.call(widget.url);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('复制链接'),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: widget.url));
                if (context.mounted) Navigator.of(context).maybePop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('分享'),
              onTap: () async {
                await SharePlus.instance.share(ShareParams(text: widget.url));
                if (context.mounted) Navigator.of(context).maybePop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.language),
              title: const Text('用系统浏览器打开'),
              onTap: () async {
                await launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication);
                if (context.mounted) Navigator.of(context).maybePop();
              },
            ),
            if (_saving)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}

class _PreviewImage extends StatelessWidget {
  const _PreviewImage({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.startsWith('data:')) {
      try {
        final bytes = base64Decode(value.split(',').last);
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.memory(
            bytes,
            width: 56,
            height: 56,
            cacheWidth: 56,
            fit: BoxFit.cover,
          ),
        );
      } catch (_) {
        return const SizedBox.shrink();
      }
    }
    if (value.startsWith('http')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          value,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
