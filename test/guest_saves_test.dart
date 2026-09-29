import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/core/providers.dart';
import 'package:liz/core/repository/repositories.dart';
import 'package:liz/features/track/guest_saves.dart';
import 'package:liz/features/track/track_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Saving used to open the sign-in sheet: the first thing Liz asked of a new
/// visitor was an account. A save now works at once, and moves into the
/// account on sign-in. These pin both halves, and that nothing is lost or
/// doubled on the way.

class _SignedIn extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool value) => state = value;
}

final _signedIn = NotifierProvider<_SignedIn, bool>(_SignedIn.new);

class _FakeTrack implements TrackRepository {
  final Set<String> server = {};
  final List<String> writes = [];

  @override
  Future<Set<String>> bookmarkedToolIds() async => {...server};

  @override
  Future<bool> toggleBookmark(String toolId) async {
    writes.add(toolId);
    if (server.remove(toolId)) return false;
    server.add(toolId);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer _container(_FakeTrack repo) {
  return ProviderContainer(
    overrides: [
      isSignedInProvider.overrideWith((ref) => ref.watch(_signedIn)),
      // The controller rebuilds when the user changes; follow the flag.
      currentUserProvider.overrideWith((ref) {
        ref.watch(_signedIn);
        return null;
      }),
      trackRepositoryProvider.overrideWithValue(repo),
    ],
  );
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a guest save stays in the browser and needs no account', () async {
    final repo = _FakeTrack();
    final c = _container(repo);
    addTearDown(c.dispose);
    c.read(bookmarkControllerProvider);
    await _settle();

    final added = await c.read(bookmarkControllerProvider.notifier).toggle('a');
    expect(added, isTrue);
    expect(c.read(bookmarkControllerProvider), {'a'});
    expect(repo.writes, isEmpty, reason: 'nothing goes to the server yet');

    final prefs = await SharedPreferences.getInstance();
    expect(GuestSaves(prefs).read(), {'a'});
  });

  test('signing in moves guest saves into the account, once', () async {
    final repo = _FakeTrack()..server.add('already');
    final c = _container(repo);
    addTearDown(c.dispose);
    c.read(bookmarkControllerProvider);
    await _settle();

    final ctrl = c.read(bookmarkControllerProvider.notifier);
    await ctrl.toggle('a');
    await ctrl.toggle('already'); // saved as a guest and in the account

    c.read(_signedIn.notifier).set(true);
    c.read(bookmarkControllerProvider);
    await _settle();

    expect(c.read(bookmarkControllerProvider), {'a', 'already'});
    // "already" was in the account: toggling it would have removed it.
    expect(repo.writes, ['a']);
    final prefs = await SharedPreferences.getInstance();
    expect(GuestSaves(prefs).read(), isEmpty, reason: 'merged, then cleared');
  });

  test('unsaving as a guest removes it', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final saves = GuestSaves(prefs);
    expect(await saves.toggle('x'), isTrue);
    expect(await saves.toggle('x'), isFalse);
    expect(saves.read(), isEmpty);
  });
}
