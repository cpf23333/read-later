import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/site.dart';
import '../../providers.dart';

/// 站点列表状态。
class SitesState {
  final List<Site> sites;
  final bool loading;
  final String? error;

  const SitesState({this.sites = const [], this.loading = false, this.error});

  SitesState copyWith({
    List<Site>? sites,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return SitesState(
      sites: sites ?? this.sites,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// 站点页加载与删除。
class SitesNotifier extends Notifier<SitesState> {
  @override
  SitesState build() => const SitesState();

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final sites = await ref.read(apiClientProvider).listSites();
      state = state.copyWith(sites: sites, loading: false, clearError: true);
    } catch (error) {
      state = state.copyWith(loading: false, error: '$error');
    }
  }

  Future<void> deleteSite(String id) async {
    final index = state.sites.indexWhere((s) => s.id == id);
    if (index < 0) return;

    final removed = state.sites[index];
    final remaining = List<Site>.from(state.sites)..removeAt(index);
    state = state.copyWith(sites: remaining, clearError: true);

    try {
      await ref.read(apiClientProvider).deleteSite(id);
    } catch (error) {
      final restored = List<Site>.from(state.sites)..insert(index, removed);
      state = state.copyWith(sites: restored, error: '$error');
    }
  }

  Future<void> updateUserAgent(
    Site site, {
    required String mode,
    String? userAgent,
  }) async {
    final updated = await ref
        .read(apiClientProvider)
        .updateSite(site.id, userAgentMode: mode, userAgent: userAgent);
    state = state.copyWith(
      sites: [
        for (final item in state.sites) item.id == updated.id ? updated : item,
      ],
      clearError: true,
    );
  }
}
