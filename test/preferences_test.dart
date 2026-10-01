import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liz/core/providers.dart';
import 'package:liz/core/repository/mock_repositories.dart';
import 'package:liz/features/profile/data_export.dart';
import 'package:liz/features/profile/preferences.dart';
import 'package:liz/shared/models/user_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Interests and alert choices: kept in the browser for a visitor, in a
/// private row once signed in, and moved across on sign-in. The picker is
/// offered once, after the second save — never as a wall before the first.

class _SignedIn extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
}

final _signedIn = NotifierProvider<_SignedIn, bool>(_SignedIn.new);

ProviderContainer _container(MockTrackRepository track) => ProviderContainer(
  overrides: [
    isSignedInProvider.overrideWith((ref) => ref.watch(_signedIn)),
    currentUserProvider.overrideWith((ref) {
      ref.watch(_signedIn);
      return null;
    }),
    trackRepositoryProvider.overrideWithValue(track),
  ],
);

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

MockTrackRepository _track() {
  final c = ProviderContainer();
  final track = c.read(trackRepositoryProvider) as MockTrackRepository;
  return track;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a visitor\'s interests stay in the browser', () async {
    final track = _track();
    final c = _container(track);
    addTearDown(c.dispose);
    c.read(preferencesProvider);
    await _settle();

    await c.read(preferencesProvider.notifier).setInterests(['ai-video']);
    expect(c.read(preferencesProvider).interests, ['ai-video']);
    expect(await track.preferences(), isNull, reason: 'no account to save to');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('liz.interests'), ['ai-video']);
  });

  test('signing in moves them into an account that has none', () async {
    final track = _track();
    final c = _container(track);
    addTearDown(c.dispose);
    c.read(preferencesProvider);
    await _settle();
    await c.read(preferencesProvider.notifier).setInterests(['ai-audio']);

    c.read(_signedIn.notifier).set(true);
    c.read(preferencesProvider);
    await _settle();
    expect((await track.preferences())?.interests, ['ai-audio']);
  });

  test('an account\'s own choices win over the browser\'s', () async {
    final track = _track();
    await track.savePreferences(
      const UserPrefs(interests: ['ai-dev'], risingAlerts: false),
    );
    SharedPreferences.setMockInitialValues({
      'liz.interests': ['ai-image'],
    });
    final c = _container(track);
    addTearDown(c.dispose);
    c.read(_signedIn.notifier).set(true);
    c.read(preferencesProvider);
    await _settle();
    expect(c.read(preferencesProvider).interests, ['ai-dev']);
    expect(c.read(preferencesProvider).risingAlerts, isFalse);
  });

  test('the picker is offered once, after the second save', () async {
    final c = _container(_track());
    addTearDown(c.dispose);
    c.read(preferencesProvider);
    await _settle();
    final ctrl = c.read(preferencesProvider.notifier);
    expect(await ctrl.shouldAskAfterSave(1), isFalse);
    expect(await ctrl.shouldAskAfterSave(2), isTrue);
    expect(await ctrl.shouldAskAfterSave(2), isFalse, reason: 'only once');
  });

  test('the export holds the account\'s own data', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(authRepositoryProvider).signInAsDemo();
    final data = await c.read(Provider((ref) => collectMyData(ref)));
    expect(data['profile'], isA<Map>());
    expect(data.keys, containsAll(['saved_tools', 'reviews', 'posts']));
    expect(data['about'], contains('not included'));
  });
}
