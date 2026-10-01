import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/core/cache.dart';

/// The grace period is the whole point of [cacheFor]: too short and going back
/// refetches what was just on screen, too long — or absent, as before — and a
/// session's every category and search term stays in memory.

var _builds = 0;

final _cached = Provider.autoDispose<int>((ref) {
  cacheFor(ref, const Duration(milliseconds: 120));
  return ++_builds;
});

final _uncached = Provider.autoDispose<int>((ref) => ++_builds);

void main() {
  setUp(() => _builds = 0);

  test('a cached provider survives losing its last listener', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.listen(_cached, (_, _) {}).close();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // Still inside the grace period, so coming back is instant and free.
    container.listen(_cached, (_, _) {}).close();
    expect(_builds, 1);
  });

  test('and is dropped once the grace period passes', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.listen(_cached, (_, _) {}).close();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    container.listen(_cached, (_, _) {}).close();
    expect(_builds, 2, reason: 'the cached value should have expired');
  });

  test('returning before the timer fires cancels the disposal', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Leave and come back three times, each well inside the window. Without
    // onResume cancelling the pending timer, the first departure's timer would
    // still fire and drop a provider that is being watched.
    for (var i = 0; i < 3; i++) {
      container.listen(_cached, (_, _) {}).close();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    container.listen(_cached, (_, _) {}).close();

    expect(_builds, 1);
  });

  test(
    'without the grace period, leaving discards the value at once',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.listen(_uncached, (_, _) {}).close();
      // Disposal is scheduled rather than immediate, so give it the same 20ms
      // the cached provider survived above — the contrast is the point.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      container.listen(_uncached, (_, _) {}).close();

      // This is the behaviour search results want: nothing outlives its query.
      expect(_builds, 2);
    },
  );
}
