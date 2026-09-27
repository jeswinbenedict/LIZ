import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cache.dart';
import '../../core/providers.dart';
import '../../core/ui_state.dart';
import '../../shared/models/tool.dart';

/// Immutable key identifying a tool feed (used for the family provider).
@immutable
class FeedKey {
  const FeedKey({
    this.sort = ToolSort.trending,
    this.category,
    this.tag,
    this.search,
    this.pricing,
  });
  final ToolSort sort;
  final String? category;
  final String? tag;
  final String? search;

  /// Null means any price.
  final PricingType? pricing;

  ToolQuery toQuery({String? cursor}) => ToolQuery(
    sort: sort,
    categorySlug: category,
    tag: tag,
    search: search,
    cursor: cursor,
    pricing: pricing,
  );

  @override
  bool operator ==(Object other) =>
      other is FeedKey &&
      other.sort == sort &&
      other.category == category &&
      other.tag == tag &&
      other.search == search &&
      other.pricing == pricing;

  @override
  int get hashCode => Object.hash(sort, category, tag, search, pricing);
}

@immutable
class FeedState {
  const FeedState({
    this.items = const [],
    this.loading = true,
    this.loadingMore = false,
    this.cursor,
    this.error,
  });

  final List<Tool> items;
  final bool loading;
  final bool loadingMore;
  final String? cursor;
  final Object? error;

  bool get hasMore => cursor != null;

  FeedState copyWith({
    List<Tool>? items,
    bool? loading,
    bool? loadingMore,
    String? cursor,
    bool clearCursor = false,
    Object? error,
    bool clearError = false,
  }) => FeedState(
    items: items ?? this.items,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    cursor: clearCursor ? null : (cursor ?? this.cursor),
    error: clearError ? null : (error ?? this.error),
  );
}

class ToolFeedController extends Notifier<FeedState> {
  ToolFeedController(this._key);
  final FeedKey _key;

  @override
  FeedState build() {
    // Flicking between sorts and categories is the normal way to browse, so
    // each feed survives a few minutes after you leave it — but a session that
    // visits thirty categories no longer holds thirty feeds forever.
    cacheFor(ref, const Duration(minutes: 5));
    _fetch();
    return const FeedState();
  }

  /// Re-reads the feed when it has had time to go stale.
  ///
  /// The catalog changes on a daily cron, so a realtime subscription would hold
  /// a socket open per category and sort to deliver almost nothing (and, for
  /// approvals, would need REPLICA IDENTITY FULL on a table carrying a 384-dim
  /// vector). Refreshing when someone returns to a tab they left open covers
  /// the case that actually happens, at no standing cost.
  static const _staleAfter = Duration(minutes: 5);
  DateTime _loadedAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> refreshIfStale() {
    if (state.loading || state.loadingMore) return Future.value();
    if (DateTime.now().difference(_loadedAt) < _staleAfter) {
      return Future.value();
    }
    return load();
  }

  Future<void> load() {
    state = const FeedState(loading: true);
    return _fetch();
  }

  Future<void> _fetch() async {
    try {
      final page = await ref
          .read(contentRepositoryProvider)
          .tools(_key.toQuery());
      if (!ref.mounted) return;
      _loadedAt = DateTime.now();
      state = FeedState(items: page.items, loading: false, cursor: page.cursor);
    } catch (e) {
      if (!ref.mounted) return;
      state = FeedState(loading: false, error: e);
    }
  }

  Future<void> refresh() => load();

  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasMore) return;
    state = state.copyWith(loadingMore: true);
    try {
      final page = await ref
          .read(contentRepositoryProvider)
          .tools(_key.toQuery(cursor: state.cursor));
      if (!ref.mounted) return;
      state = state.copyWith(
        items: [...state.items, ...page.items],
        loadingMore: false,
        cursor: page.cursor,
        clearCursor: page.cursor == null,
      );
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(loadingMore: false, error: e);
    }
  }
}

final toolFeedProvider = NotifierProvider.autoDispose
    .family<ToolFeedController, FeedState, FeedKey>(ToolFeedController.new);

/// The price filter on the Discover screen. Null means any price.
final discoverPricingProvider = uiStateProvider<PricingType?>(null);

/// The currently selected sort on the Discover screen.
final discoverSortProvider = uiStateProvider<ToolSort>(ToolSort.trending);

/// The currently selected category slug (null = All).
final discoverCategoryProvider = uiStateProvider<String?>(null);
