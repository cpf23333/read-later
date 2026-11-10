import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/import_link.dart';
import '../../core/models/link.dart';
import '../../providers.dart';

/// 收藏库状态。
class LibraryState {
  final List<LinkItem> links;
  final int total;
  final int page;
  final bool loading;
  final bool loadingMore;
  final String? error;
  final String search;
  final String sortBy;
  final bool sortDesc;
  final String? domain;

  const LibraryState({
    this.links = const [],
    this.total = 0,
    this.page = 1,
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.search = '',
    this.sortBy = 'created_at',
    this.sortDesc = true,
    this.domain,
  });

  bool get hasMore => links.length < total;

  LibraryState copyWith({
    List<LinkItem>? links,
    int? total,
    int? page,
    bool? loading,
    bool? loadingMore,
    String? error,
    bool clearError = false,
    String? search,
    String? sortBy,
    bool? sortDesc,
    String? domain,
    bool clearDomain = false,
  }) {
    return LibraryState(
      links: links ?? this.links,
      total: total ?? this.total,
      page: page ?? this.page,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      error: clearError ? null : (error ?? this.error),
      search: search ?? this.search,
      sortBy: sortBy ?? this.sortBy,
      sortDesc: sortDesc ?? this.sortDesc,
      domain: clearDomain ? null : (domain ?? this.domain),
    );
  }
}

/// 收藏库分页/搜索/删除。
class LibraryNotifier extends Notifier<LibraryState> {
  static const pageSize = 50;

  Timer? _searchDebounce;

  @override
  LibraryState build() {
    ref.onDispose(() => _searchDebounce?.cancel());
    return const LibraryState();
  }

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true, page: 1);
    try {
      final result = await ref
          .read(apiClientProvider)
          .listLinks(
            page: 1,
            pageSize: pageSize,
            search: state.search.isEmpty ? null : state.search,
            domain: state.domain,
            sortBy: state.sortBy,
            sortOrder: state.sortDesc ? 'desc' : 'asc',
          );
      state = state.copyWith(
        links: result.links,
        total: result.total,
        page: 1,
        loading: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(loading: false, error: '$error');
    }
  }

  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || !state.hasMore) return;

    state = state.copyWith(loadingMore: true);
    try {
      final nextPage = state.page + 1;
      final result = await ref
          .read(apiClientProvider)
          .listLinks(
            page: nextPage,
            pageSize: pageSize,
            search: state.search.isEmpty ? null : state.search,
            domain: state.domain,
            sortBy: state.sortBy,
            sortOrder: state.sortDesc ? 'desc' : 'asc',
          );
      final existingIds = state.links.map((l) => l.id).toSet();
      final merged = [
        ...state.links,
        ...result.links.where((l) => !existingIds.contains(l.id)),
      ];
      state = state.copyWith(
        links: merged,
        total: result.total,
        page: nextPage,
        loadingMore: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(loadingMore: false, error: '$error');
    }
  }

  void setSearch(String value) {
    state = state.copyWith(search: value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), refresh);
  }

  void setSort({String? sortBy, bool? sortDesc}) {
    state = state.copyWith(sortBy: sortBy, sortDesc: sortDesc);
    refresh();
  }

  Future<void> setDomain(String? domain) async {
    state = state.copyWith(domain: domain, clearDomain: domain == null);
    await refresh();
  }

  Future<void> deleteLink(String id) async {
    final index = state.links.indexWhere((l) => l.id == id);
    if (index < 0) return;

    final removed = state.links[index];
    final remaining = List<LinkItem>.from(state.links)..removeAt(index);
    state = state.copyWith(
      links: remaining,
      total: state.total - 1,
      clearError: true,
    );

    try {
      await ref.read(apiClientProvider).deleteLink(id);
    } catch (error) {
      final restored = List<LinkItem>.from(state.links)..insert(index, removed);
      state = state.copyWith(
        links: restored,
        total: state.total + 1,
        error: '$error',
      );
    }
  }

  Future<DedupeResult> dedupe() async {
    final result = await ref.read(apiClientProvider).dedupeLinks();
    await refresh();
    return result;
  }

  Future<void> batchDelete(List<String> ids) async {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;

    final removed = state.links.where((l) => idSet.contains(l.id)).toList();
    final remaining = state.links.where((l) => !idSet.contains(l.id)).toList();
    state = state.copyWith(
      links: remaining,
      total: state.total - removed.length,
      clearError: true,
    );

    try {
      await ref.read(apiClientProvider).batchDeleteLinks(ids);
    } catch (error) {
      await refresh();
      state = state.copyWith(error: '$error');
    }
  }
}
