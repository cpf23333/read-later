import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/domain_stat.dart';
import '../../core/models/link.dart';
import '../../core/models/site.dart';
import '../../core/util/origin.dart';
import '../../providers.dart';
import 'browser_toolbar.dart';

/// 浏览器新标签页：搜索/地址输入 + 收藏站点 + 最近收藏 + 常收藏域名。
class NewTabPage extends ConsumerStatefulWidget {
  const NewTabPage({super.key, required this.onNavigate});

  final ValueChanged<String> onNavigate;

  @override
  ConsumerState<NewTabPage> createState() => _NewTabPageState();
}

class _NewTabPageState extends ConsumerState<NewTabPage> {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  late Future<List<LinkItem>> _recentLinks;
  late Future<List<DomainStat>> _domains;

  @override
  void initState() {
    super.initState();
    if (ref.read(sitesProvider).sites.isEmpty) {
      Future.microtask(() => ref.read(sitesProvider.notifier).refresh());
    }
    _recentLinks = _loadRecentLinks();
    _domains = _loadDomains();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<List<LinkItem>> _loadRecentLinks() async {
    try {
      final result = await ref
          .read(apiClientProvider)
          .listLinks(
            page: 1,
            pageSize: 8,
            sortBy: 'created_at',
            sortOrder: 'desc',
          );
      return result.links;
    } catch (_) {
      return const [];
    }
  }

  Future<List<DomainStat>> _loadDomains() async {
    try {
      return await ref.read(apiClientProvider).listDomains();
    } catch (_) {
      return const [];
    }
  }

  void _submit(String value) {
    final resolved = normalizeUserInput(value);
    if (resolved.isEmpty) return;
    _inputFocus.unfocus();
    widget.onNavigate(resolved);
  }

  void _openUrl(String url) {
    _inputFocus.unfocus();
    widget.onNavigate(url);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sites = ref.watch(sitesProvider).sites;

    return ColoredBox(
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('稍后再看', style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _inputController,
                      focusNode: _inputFocus,
                      textInputAction: TextInputAction.go,
                      onSubmitted: _submit,
                      decoration: InputDecoration(
                        hintText: '搜索或输入网址',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        filled: true,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _SectionTitle(title: '常用站点', theme: theme),
                    const SizedBox(height: 10),
                    _buildSites(sites, theme),
                    const SizedBox(height: 26),
                    _SectionTitle(title: '最近收藏', theme: theme),
                    const SizedBox(height: 6),
                    _buildRecentLinks(theme),
                    const SizedBox(height: 26),
                    _SectionTitle(title: '常收藏域名', theme: theme),
                    const SizedBox(height: 8),
                    _buildDomains(theme),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSites(List<Site> sites, ThemeData theme) {
    if (sites.isEmpty) {
      return Text(
        '长按网页链接，选择“收藏主站”后会显示在这里',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final site in sites.take(12))
          ActionChip(
            avatar: CircleAvatar(
              child: Text(
                ((hostOf(site.url) ?? site.url).isEmpty
                        ? '?'
                        : (hostOf(site.url) ?? site.url).substring(0, 1))
                    .toUpperCase(),
              ),
            ),
            label: Text(
              site.title.isEmpty ? (hostOf(site.url) ?? site.url) : site.title,
              overflow: TextOverflow.ellipsis,
            ),
            onPressed: () => _openUrl(site.url),
          ),
      ],
    );
  }

  Widget _buildRecentLinks(ThemeData theme) {
    return FutureBuilder<List<LinkItem>>(
      future: _recentLinks,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: LinearProgressIndicator(),
          );
        }
        final links = snapshot.data ?? const <LinkItem>[];
        if (links.isEmpty) {
          return Text(
            '还没有收藏，打开一个页面并通过顶部书签按钮收藏',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );
        }
        return Column(
          children: [
            for (final link in links.take(5))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  child: Text(
                    (link.title.isEmpty
                            ? (hostOf(link.url) ?? '?')
                            : link.title)
                        .substring(0, 1)
                        .toUpperCase(),
                  ),
                ),
                title: Text(
                  link.title.isEmpty
                      ? (hostOf(link.url) ?? link.url)
                      : link.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  hostOf(link.url) ?? link.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => _openUrl(link.url),
              ),
          ],
        );
      },
    );
  }

  Widget _buildDomains(ThemeData theme) {
    return FutureBuilder<List<DomainStat>>(
      future: _domains,
      builder: (context, snapshot) {
        final domains = snapshot.data ?? const <DomainStat>[];
        if (domains.isEmpty) {
          return Text(
            '暂无域名数据',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in domains.take(12))
              ActionChip(
                label: Text('${item.domain} (${item.count})'),
                onPressed: () => _openUrl('https://${item.domain}'),
              ),
          ],
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.theme});

  final String title;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}
