import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Screen state that any widget may set outright: which filter is on, which
/// sort is chosen, which rows are ticked.
///
/// Riverpod 3 moved `StateProvider` into its legacy library. This is the same
/// idea as an ordinary [Notifier], so the providers that used it read the same
/// way without depending on an API marked for removal.
class UiState<T> extends Notifier<T> {
  UiState(this._initial);
  final T _initial;

  @override
  T build() => _initial;

  void set(T value) => state = value;

  void update(T Function(T current) change) => state = change(state);
}

/// A provider of [UiState] starting at [initial].
NotifierProvider<UiState<T>, T> uiStateProvider<T>(T initial) =>
    NotifierProvider<UiState<T>, T>(() => UiState<T>(initial));
