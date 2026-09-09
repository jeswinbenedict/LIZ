import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers.dart';
import '../../shared/models/app_notification.dart';

@immutable
class AlertsState {
  const AlertsState({this.items = const [], this.loading = true, this.error});

  final List<AppNotification> items;
  final bool loading;
  final Object? error;

  int get unread => items.where((n) => !n.read).length;

  AlertsState copyWith({
    List<AppNotification>? items,
    bool? loading,
    Object? error,
    bool clearError = false,
  }) => AlertsState(
    items: items ?? this.items,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
  );
}

/// The alerts inbox.
///
/// Alerts are written by the database when something happens to a tool you
/// follow, so this only reads them. New ones arrive over Realtime rather than
/// by polling: the whole point is that you hear about a change without having
/// gone looking for it.
class AlertsController extends StateNotifier<AlertsState> {
  AlertsController(this._ref) : super(const AlertsState()) {
    load();
    _subscribe();
  }

  final Ref _ref;
  RealtimeChannel? _channel;

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final items = await _ref.read(trackRepositoryProvider).notifications();
      if (!mounted) return;
      state = AlertsState(items: items, loading: false);
    } catch (e) {
      if (!mounted) return;
      state = AlertsState(loading: false, error: e);
    }
  }

  Future<void> refresh() => load();

  Future<void> markRead(AppNotification n) async {
    if (n.read) return;
    // Optimistic: the badge should drop the moment it is tapped, not after a
    // round trip. A failed write only means it is still unread on the server,
    // and the next load will say so.
    state = state.copyWith(
      items: [
        for (final item in state.items)
          item.id == n.id ? item.copyWith(read: true) : item,
      ],
    );
    try {
      await _ref.read(trackRepositoryProvider).markNotificationRead(n.id);
    } catch (_) {
      // Left as-is; load() is the source of truth.
    }
  }

  Future<void> markAllRead() async {
    if (state.unread == 0) return;
    state = state.copyWith(
      items: [for (final item in state.items) item.copyWith(read: true)],
    );
    try {
      await _ref.read(trackRepositoryProvider).markAllNotificationsRead();
    } catch (_) {
      // As above.
    }
  }

  void _subscribe() {
    final client = _ref.read(supabaseClientProvider);
    final uid = _ref.read(authRepositoryProvider).currentUserId;
    if (client == null || uid == null) return;
    _channel = client
        .channel('public:notifications:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          // Row-level security already limits this to the reader's own rows;
          // the filter keeps the server from sending what would be discarded.
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: _onInsert,
        )
        .subscribe();
  }

  void _onInsert(PostgresChangePayload payload) {
    if (!mounted) return;
    final item = AppNotification.fromJson(payload.newRecord);
    if (state.items.any((n) => n.id == item.id)) return;
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

final alertsControllerProvider =
    StateNotifierProvider<AlertsController, AlertsState>((ref) {
      // Rebuilt on sign-in and sign-out: alerts belong to a person, and a
      // guest must not keep showing the last account's badge.
      ref.watch(currentUserProvider);
      return AlertsController(ref);
    });

/// How many alerts are waiting, for the bell badge. Zero for a guest.
final unreadAlertsProvider = Provider<int>(
  (ref) => ref.watch(alertsControllerProvider).unread,
);
