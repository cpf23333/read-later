import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/errors.dart';
import '../../core/config/server_url.dart';
import '../../core/models/config.dart';
import '../../core/models/user_agent_rule.dart';
import '../../providers.dart';

/// 设置页：服务器配置、主题、清除浏览数据、导入说明。
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const appVersion = '1.0.0';

  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _keyController = TextEditingController();
  bool _obscureKey = true;
  bool _busy = false;
  String? _status;
  String? _urlError;

  @override
  void initState() {
    super.initState();
    _loadConfig();
    Future.microtask(() {
      if (!ref.read(globalUserAgentProvider).initialized) {
        ref.read(globalUserAgentProvider.notifier).refresh();
      }
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final config = await ref.read(configStoreProvider).read();
    if (!mounted) return;
    setState(() {
      _urlController.text = config.baseUrl;
      _keyController.text = config.apiKey;
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveAndTest() async {
    final url = _urlController.text.trim();
    final key = _keyController.text.trim();
    final urlError = validateServerUrl(url);
    if (urlError != null) {
      setState(() => _urlError = urlError);
      return;
    }
    if (key.isEmpty) {
      _snack('请填写 API Key');
      return;
    }

    final normalizedUrl = normalizeServerUrl(url)!;

    setState(() {
      _urlError = null;
      _busy = true;
      _status = null;
    });

    try {
      await ref
          .read(configStoreProvider)
          .save(
            ServerConfig(baseUrl: normalizedUrl, apiKey: key, enabled: true),
          );
      await ref.read(apiClientProvider).health();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '连接成功';
      });
      _snack('已保存，连接成功');
      // 配置变更后刷新依赖服务器的页面。
      ref.read(libraryProvider.notifier).refresh();
      ref.read(sitesProvider.notifier).refresh();
      ref.read(globalUserAgentProvider.notifier).refresh();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '连接失败';
      });
      final message = error is ApiException ? error.message : '$error';
      _snack('已保存，但连接失败：$message');
    }
  }

  Future<void> _editGlobalUserAgent() async {
    final current = ref.read(globalUserAgentProvider).rule;
    final result = await showDialog<UserAgentRule>(
      context: context,
      builder: (dialogContext) => _GlobalUserAgentDialog(rule: current),
    );
    if (result == null) return;
    try {
      await ref.read(globalUserAgentProvider.notifier).save(result);
      if (mounted) _snack('全局默认 User-Agent 已更新');
    } catch (error) {
      if (mounted) _snack('保存失败：');
    }
  }

  Future<void> _clearBrowsingData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清除浏览数据'),
        content: const Text('将清除 Cookie、缓存与本地存储，确定继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await CookieManager.instance().deleteAllCookies();
      await InAppWebViewController.clearAllCache();
      await WebStorageManager.instance().deleteAllData();
      _snack('浏览数据已清除');
    } catch (error) {
      _snack('清除失败：$error');
    }
  }

  void _showImportHelp() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('从本机浏览器导入标签页'),
        content: const SingleChildScrollView(
          child: SelectableText(
            '这是电脑上执行的一次性流程（需要 adb）：\n\n'
            '1. 手机/平板开启开发者选项与 USB 调试，保持 Chrome/Brave 运行。\n'
            '2. 电脑执行：\n'
            '   adb forward tcp:9222 localabstract:chrome_devtools_remote\n'
            '3. 电脑执行导入脚本：\n'
            '   node tools/import-tabs/import.mjs --server <服务器地址> --api-key <API Key>\n\n'
            '可选：加 --with-screenshots 通过 CDP 为每个标签页截页面预览图（会慢一些）。\n\n'
            '仅支持 Chromium 系浏览器；无线调试（adb connect）同样可用。\n免电脑方案（Shizuku / 无线调试 + app 内 ADB host）在评估中，v1 未实现。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final videoSettings = ref.watch(videoSettingsProvider);
    final globalUa = ref.watch(globalUserAgentProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('服务器', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _urlController,
            onChanged: (value) {
              setState(() => _urlError = validateServerUrl(value));
            },
            decoration: InputDecoration(
              labelText: '服务器地址',
              hintText: 'http://192.168.1.2:3000',
              errorText: _urlError,
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keyController,
            obscureText: _obscureKey,
            decoration: InputDecoration(
              labelText: 'API Key',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureKey ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _saveAndTest,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering),
            label: const Text('保存并测试连接'),
          ),
          if (_status != null) ...[
            const SizedBox(height: 8),
            Text(_status!, style: TextStyle(color: theme.colorScheme.primary)),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '内网 http 服务器可直接使用；公网部署建议启用 HTTPS。',
              style: theme.textTheme.bodySmall,
            ),
          ),
          const Divider(height: 32),
          Text('外观', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
              ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
              ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
            ],
            selected: {themeMode},
            onSelectionChanged: (selection) {
              ref.read(themeProvider.notifier).setMode(selection.first);
            },
          ),
          const Divider(height: 32),
          Text('视频播放', style: theme.textTheme.titleMedium),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('检测到视频时自动播放'),
            subtitle: const Text('用内置 Media3 播放器打开直链视频（m3u8/mpd/mp4）'),
            value: videoSettings.autoPlay,
            onChanged: (value) =>
                ref.read(videoSettingsProvider.notifier).setAutoPlay(value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('显示「播放视频」按钮'),
            subtitle: const Text('关闭后浏览器不显示视频入口；自动播放设置仍生效'),
            value: videoSettings.showPlayerButton,
            onChanged: (value) => ref
                .read(videoSettingsProvider.notifier)
                .setShowPlayerButton(value),
          ),
          const Divider(height: 32),
          Text('浏览器', style: theme.textTheme.titleMedium),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.desktop_windows_outlined),
            title: const Text('全局默认 User-Agent'),
            subtitle: Text(globalUa.rule.label),
            onTap: _editGlobalUserAgent,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('清除浏览数据'),
            subtitle: const Text('Cookie、缓存、本地存储'),
            onTap: _clearBrowsingData,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.download_outlined),
            title: const Text('从本机浏览器导入标签页'),
            subtitle: const Text('v1 需电脑 + adb，查看步骤'),
            onTap: _showImportHelp,
          ),
          const Divider(height: 32),
          Text('关于', style: theme.textTheme.titleMedium),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('版本'),
            trailing: Text(appVersion),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '数据保存在你自建的服务器上；不采集任何分析数据。',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlobalUserAgentDialog extends StatefulWidget {
  const _GlobalUserAgentDialog({required this.rule});

  final UserAgentRule rule;

  @override
  State<_GlobalUserAgentDialog> createState() => _GlobalUserAgentDialogState();
}

class _GlobalUserAgentDialogState extends State<_GlobalUserAgentDialog> {
  late String _mode;
  late final TextEditingController _customController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _mode = widget.rule.mode;
    _customController = TextEditingController(
      text: widget.rule.customUserAgent ?? '',
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
      UserAgentRule(
        mode: _mode,
        customUserAgent: _mode == 'custom' ? custom : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('全局默认 User-Agent'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
