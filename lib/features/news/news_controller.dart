import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers.dart';
import '../../shared/models/news_item.dart';

@immutable
class NewsState {
  const NewsState({
    this.items = const [],
    this.loading = true,
    this.loadingMore = false,
    this.cursor,
    this.error,
    this.live = false,
  });

  final List<NewsItem> items;
  final bool loading;
  final bool loadingMore;
  final String? cursor;
  final Object? error;

  /// True when a live Realtime subscription is active (backend connected).
  final bool live;

  bool get hasMore => cursor != null;

  NewsState copyWith({
    List<NewsItem>? items,
    bool? loading,
    bool? loadingMore,
    String? cursor,
    bool clearCursor = false,
    Object? error,
    bool clearError = false,
    bool? live,
  }) =>
      NewsState(
        items: items ?? this.items,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        cursor: clearCursor ? null : (cursor ?? this.cursor),
        error: clearError ? null : (error ?? this.error),
        live: live ?? this.live,
      );
}

/// Loads the tech-news feed and, when the live backend is connected, subscribes
/// to Supabase Realtime so newly-ingested articles appear at the top instantly.
class NewsController extends StateNotifier<NewsState> {
  NewsController(this._ref) : super(const NewsState()) {
    load();
    _subscribeRealtime();
  }

  final Ref _ref;
  RealtimeChannel? _channel;

  Future<void> load() async {
    state = const NewsState(loading: true);
    try {
      final page = await _ref.read(contentRepositoryProvider).news();
      state = state.copyWith(
        items: page.items,
        loading: false,
        cursor: page.cursor,
        clearCursor: page.cursor == null,
      );
    } catch (e) {
      state = NewsState(loading: false, error: e);
    }
  }

  Future<void> refresh() => load();

  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasMore) return;
    state = state.copyWith(loadingMore: true);
    try {
      final page =
          await _ref.read(contentRepositoryProvider).news(cursor: state.cursor);
      state = state.copyWith(
        items: [...state.items, ...page.items],
        loadingMore: false,
        cursor: page.cursor,
        clearCursor: page.cursor == null,
      );
    } catch (e) {
      state = state.copyWith(loadingMore: false, error: e);
    }
  }

  void _subscribeRealtime() {
    final client = _ref.read(supabaseClientProvider);
    if (client == null) return; // mock mode: no realtime
    _channel = client
        .channel('public:news')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'news',
          callback: _onInsert,
        )
        .subscribe((status, _) {
      if (status == RealtimeSubscribeStatus.subscribed && mounted) {
        state = state.copyWith(live: true);
      }
    });
  }

  void _onInsert(PostgresChangePayload payload) {
    if (!mounted) return;
    final row = payload.newRecord;
    if (row['status'] != 'published') return;
    final item = NewsItem.fromJson(row);
    if (state.items.any((n) => n.id == item.id)) return;
    // Prepend the freshly-ingested article.
    state = state.copyWith(items: [item, ...state.items]);
  }

  @override
  void dispose() {
    final ch = _channel;
    if (ch != null) {
      _ref.read(supabaseClientProvider)?.removeChannel(ch);
    }
    super.dispose();
  }
}

final newsControllerProvider =
    StateNotifierProvider<NewsController, NewsState>((ref) {
  return NewsController(ref);
});
