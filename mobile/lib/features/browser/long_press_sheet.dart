import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// 长按链接弹出的收藏菜单。
///
/// 打开菜单时不解析标题/图片；只有点击“收藏到稍后再看”后才开始解析，
/// 避免长按后立刻发起网络请求和页面脚本提取。
class LongPressSheet extends ConsumerStatefulWidget {
  const LongPressSheet({
    super.key,
    required this.url,
    required this.sourcePage,
    this.linkText,
    this.nearbyText,
    this.nearbyImage,
    this.extraction,
    this.onOpenInNewTab,
    this.onOpenInBackground,
  });

  final String url;
  final String sourcePage;
  final String? linkText;
  final String? nearbyText;
  final String? nearbyImage;

  /// 延迟执行的页面内提取；只有保存时才调用。
  final Future<Map<String, dynamic>> Function()? extraction;
  final ValueChanged<String>? onOpenInNewTab;
  final ValueChanged<String>? onOpenInBackground;

  @override
  ConsumerState<LongPressSheet> createState() => _LongPressSheetState();
}

class _LongPressSheetState extends ConsumerState<LongPressSheet> {
  bool _saving = false;

  Future<void> _saveLink() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final capture = ref.read(captureServiceProvider);
      final prepared = await capture.prepare(
        url: widget.url,
        linkText: widget.linkText,
        nearbyText: widget.nearbyText,
        nearbyImage: widget.nearbyImage,
        sourcePage: widget.sourcePage,
      );

      final extracted = widget.extraction == null
          ? const <String, dynamic>{}
          : await widget.extraction!();
      final extractedImage = extracted['nearbyImage'] as String?;
      final firstImage = [prepared.nearbyImage, extractedImage].firstWhere(
        (value) => value != null && value.isNotEmpty,
        orElse: () => null,
      );

      final resolvedImage = await capture.resolveNearbyImage(firstImage);
      final preview = prepared.copyWith(
        nearbyImage: resolvedImage,
        clearNearbyImage: resolvedImage == null && firstImage != null,
      );
      final caps = applyMediaCaps(nearbyImage: preview.nearbyImage);

      await capture.save(preview.copyWith(nearbyImage: caps.nearbyImage));
      if (!mounted) return;
      setState(() => _saving = false);
      Navigator.of(context).maybePop(
        LongPressResult(
          saved: true,
          kind: 'link',
          droppedImage: caps.droppedImage,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：${_message(error)}')));
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
      Navigator.of(
        context,
      ).maybePop(const LongPressResult(saved: true, kind: 'site'));
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('收藏主站失败：${_message(error)}')));
    }
  }

  String _message(Object error) {
    if (error is ApiException) return error.message;
    return '$error';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.linkText?.trim();
    final host = hostOf(widget.url);

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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title == null || title.isEmpty
                            ? (host ?? widget.url)
                            : title,
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
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            ListTile(
              enabled: !_saving,
              leading: const Icon(Icons.bookmark_add_outlined),
              title: const Text('收藏到稍后再看'),
              onTap: _saveLink,
            ),
            ListTile(
              enabled: !_saving,
              leading: const Icon(Icons.public_outlined),
              title: Text('收藏主站 ${host ?? ''}'.trim()),
              onTap: _saveSite,
            ),
            ListTile(
              leading: const Icon(Icons.tab_unselected),
              title: const Text('后台打开新标签页'),
              onTap: () {
                Navigator.of(context).maybePop();
                widget.onOpenInBackground?.call(widget.url);
              },
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
                await launchUrl(
                  Uri.parse(widget.url),
                  mode: LaunchMode.externalApplication,
                );
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
