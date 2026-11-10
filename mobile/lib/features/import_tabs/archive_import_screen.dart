import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/import_link.dart';
import '../../providers.dart';

/// 从 PC 导出的 readlater-tabs.zip 导入标签页。
class ArchiveImportScreen extends ConsumerStatefulWidget {
  const ArchiveImportScreen({super.key});

  @override
  ConsumerState<ArchiveImportScreen> createState() =>
      _ArchiveImportScreenState();
}

class _ArchiveTab {
  final String url;
  final String title;
  final Uint8List? screenshot;

  const _ArchiveTab({required this.url, required this.title, this.screenshot});
}

class _ArchiveImportScreenState extends ConsumerState<ArchiveImportScreen> {
  List<_ArchiveTab> _tabs = const [];
  String? _fileName;
  String? _error;
  String? _status;
  bool _busy = false;

  Future<void> _pickArchive() async {
    setState(() {
      _error = null;
      _status = null;
    });
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      final file = files.isEmpty ? null : files.first;
      final bytes = file == null ? null : await file.readAsBytes();
      if (file == null || bytes == null) return;
      if (bytes.length > 200 * 1024 * 1024) {
        throw const FormatException('压缩包不能超过 200MB');
      }

      final archive = ZipDecoder().decodeBytes(bytes);
      final manifestFile = archive.findFile('manifest.json');
      if (manifestFile == null) {
        throw const FormatException('压缩包中缺少 manifest.json');
      }
      final manifest = jsonDecode(
        utf8.decode(manifestFile.content as List<int>),
      );
      if (manifest is! Map<String, dynamic> ||
          manifest['format'] != 'readlater-tabs' ||
          manifest['tabs'] is! List) {
        throw const FormatException('不是有效的 ReadLater 标签页压缩包');
      }

      final tabs = <_ArchiveTab>[];
      for (final raw in manifest['tabs'] as List) {
        if (raw is! Map) continue;
        final url = raw['url'];
        if (url is! String || !url.startsWith('http')) continue;
        Uint8List? screenshot;
        final screenshotPath = raw['screenshot'];
        if (screenshotPath is String && screenshotPath.isNotEmpty) {
          final imageFile = archive.findFile(screenshotPath);
          if (imageFile != null) {
            screenshot = Uint8List.fromList(imageFile.content as List<int>);
          }
        }
        tabs.add(
          _ArchiveTab(
            url: url,
            title: (raw['title'] as String?) ?? '',
            screenshot: screenshot,
          ),
        );
        if (tabs.length >= 5000) break;
      }
      if (tabs.isEmpty) {
        throw const FormatException('压缩包里没有可导入的标签页');
      }

      if (!mounted) return;
      setState(() {
        _fileName = file.name;
        _tabs = tabs;
        _status = '读取到 ${tabs.length} 个标签页，等待导入';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _tabs = const [];
        _fileName = null;
        _status = null;
      });
    }
  }

  Future<void> _import() async {
    if (_busy || _tabs.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = '正在导入 0/${_tabs.length}...';
    });

    try {
      final api = ref.read(apiClientProvider);
      final links = <ImportLink>[];
      var failed = 0;

      for (var i = 0; i < _tabs.length; i++) {
        final tab = _tabs[i];
        String? screenshotPath;
        final screenshot = tab.screenshot;
        if (screenshot != null && screenshot.isNotEmpty) {
          try {
            final dataUrl = 'data:image/png;base64,${base64Encode(screenshot)}';
            screenshotPath = await api.uploadImagePath(
              dataUrl,
              filename: 'tab-preview.png',
              purpose: 'screenshot',
            );
          } catch (_) {
            failed++;
          }
        }
        links.add(
          ImportLink(
            url: tab.url,
            title: tab.title,
            screenshot: screenshotPath,
          ),
        );
        if (!mounted) return;
        setState(() => _status = '正在导入 ${i + 1}/${_tabs.length}...');
      }

      var imported = 0;
      var skipped = 0;
      for (var start = 0; start < links.length; start += 200) {
        final end = (start + 200).clamp(0, links.length);
        final result = await api.importLinks(links.sublist(start, end));
        imported += result.imported;
        skipped += result.skipped;
        failed += result.failed;
        if (!mounted) return;
        setState(() => _status = '正在导入 $imported/${links.length}...');
      }

      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '导入完成：成功 $imported，跳过 $skipped，失败 $failed';
      });
      ref.read(libraryProvider.notifier).refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入完成：成功 $imported，跳过 $skipped，失败 $failed')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = null;
        _error = '导入失败：$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('从压缩包导入标签页')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '在电脑上执行导出脚本生成 readlater-tabs.zip，'
                '再把 zip 传到手机，在这里选择并导入。\n\n'
                '脚本位置：仓库根目录 tools/import-tabs/import.mjs（App 不内置；'
                '需要 Node.js 24+ 和 adb）。\n\n'
                '压缩包内包含 manifest.json；如导出时带截图，'
                '截图也会随文件一起导入。',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _pickArchive,
            icon: const Icon(Icons.folder_open),
            label: const Text('选择 readlater-tabs.zip'),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_status!, style: theme.textTheme.bodyMedium),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          if (_fileName != null) ...[
            const SizedBox(height: 12),
            Text('文件：$_fileName', style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Text('预览（${_tabs.length}）', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final tab in _tabs.take(50))
              Card(
                child: ListTile(
                  leading: _Thumbnail(data: tab.screenshot),
                  title: Text(
                    tab.title.isEmpty ? tab.url : tab.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    tab.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            if (_tabs.length > 50)
              Text(
                '仅显示前 50 条，实际共 ${_tabs.length} 条',
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _import,
              icon: const Icon(Icons.download),
              label: Text('导入 ${_tabs.length} 个标签页'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.data});

  final Uint8List? data;

  @override
  Widget build(BuildContext context) {
    if (data == null) {
      return const Icon(Icons.tab);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.memory(
        data!,
        width: 56,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const Icon(Icons.tab),
      ),
    );
  }
}
