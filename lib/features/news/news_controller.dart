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
  }) => NewsState(
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
class NewsController extends Notifier<NewsState> {
  @override
  NewsState build() {
    _subscribeRealtime();
    _fetch();
    return const NewsState();
  }

  Future<void> load() {
    state = const NewsState(loading: true);
    return _fetch();
  }

  Future<void> _fetch() async {
    try {
      final page = await ref.read(contentRepositoryProvider).news();
      if (!ref.mounted) return;
      state = state.copyWith(
        items: page.items,
        loading: false,
        cursor: page.cursor,
        clearCursor: page.cursor == null,
      );
    } catch (e) {
      if (!ref.mounted) return;
      state = NewsState(loading: false, error: e);
    }
  }

  Future<void> refresh() => load();

  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasMore) return;
    state = state.copyWith(loadingMore: true);
    try {
      final page = await ref
          .read(contentRepositoryProvider)
          .news(cursor: state.cursor);
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

  void _subscribeRealtime() {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return; // mock mode: no realtime
    final channel = client
        .channel('public:news')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'news',
          callback: _onInsert,
        )
        .subscribe((status, _) {
          if (status == RealtimeSubscribeStatus.subscribed && ref.mounted) {
            state = state.copyWith(live: true);
          }
        });
    ref.onDispose(() => client.removeChannel(channel));
  }

  void _onInsert(PostgresChangePayload payload) {
    if (!ref.mounted) return;
    final row = payload.newRecord;
    if (row['status'] != 'published') return;
    final item = NewsItem.fromJson(row);
    if (state.items.any((n) => n.id == item.id)) return;
    // Prepend the freshly-ingested article.
    state = state.copyWith(items: [item, ...state.items]);
  }
}

final newsControllerProvider = NotifierProvider<NewsController, NewsState>(
  NewsController.new,
);
