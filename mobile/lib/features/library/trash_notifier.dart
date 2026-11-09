import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/link.dart';
import '../../core/models/site.dart';
import '../../providers.dart';

/// 回收站状态（链接 + 站点）。
class TrashState {
  final List<TrashItem> links;
  final List<Site> sites;
  final bool loading;
  final String? error;

  const TrashState({
    this.links = const [],
    this.sites = const [],
    this.loading = false,
    this.error,
  });

  TrashState copyWith({
    List<TrashItem>? links,
    List<Site>? sites,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return TrashState(
      links: links ?? this.links,
      sites: sites ?? this.sites,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// 回收站加载、还原、永久删除。
class TrashNotifier extends Notifier<TrashState> {
  @override
  TrashState build() => const TrashState();

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = ref.read(apiClientProvider);
      final results = await Future.wait([
        api.listTrash(),
        api.listSiteTrash(),
      ]);
      state = state.copyWith(
        links: results[0] as List<TrashItem>,
        sites: results[1] as List<Site>,
        loading: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(loading: false, error: '$error');
    }
  }

  Future<void> restoreLink(String id) async {
    try {
      await ref.read(apiClientProvider).restoreTrash(id);
      state = state.copyWith(
        links: state.links.where((item) => item.id != id).toList(),
      );
    } catch (error) {
      state = state.copyWith(error: '$error');
    }
  }

  Future<void> purgeLink(String id) async {
    try {
      await ref.read(apiClientProvider).purgeTrash(id);
      state = state.copyWith(
        links: state.links.where((item) => item.id != id).toList(),
      );
    } catch (error) {
      state = state.copyWith(error: '$error');
    }
  }

  Future<void> restoreSite(String id) async {
    try {
      await ref.read(apiClientProvider).restoreSite(id);
      state = state.copyWith(
        sites: state.sites.where((item) => item.id != id).toList(),
      );
    } catch (error) {
      state = state.copyWith(error: '$error');
    }
  }

  Future<void> purgeSite(String id) async {
    try {
      await ref.read(apiClientProvider).purgeSite(id);
      state = state.copyWith(
        sites: state.sites.where((item) => item.id != id).toList(),
      );
    } catch (error) {
      state = state.copyWith(error: '$error');
    }
  }
}
