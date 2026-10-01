import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/settings_controller.dart';
import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../shared/models/user_prefs.dart';
import '../../shared/widgets/page_header.dart';

/// What a person has told Liz about themselves: interests and alert choices.
///
/// Stored in the browser for a visitor, and in their private
/// user_preferences row once signed in (migration 0050). On sign-in, a
/// visitor's interests move into the account if it has none yet — the same
/// rule saves follow (GuestSaves).
class PreferencesController extends Notifier<UserPrefs> {
  static const _interestsKey = 'liz.interests';
  static const _askedKey = 'liz.interests_asked';
  int _generation = 0;

  @override
  UserPrefs build() {
    ref.watch(isSignedInProvider);
    ref.watch(currentUserProvider);
    _load();
    return const UserPrefs();
  }

  Future<SharedPreferences?> _prefs() async {
    try {
      return await ref.read(sharedPreferencesProvider.future);
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final local = await _prefs();
    final guest = UserPrefs(
      interests: local?.getStringList(_interestsKey) ?? const [],
    );
    var loaded = guest;
    if (ref.read(isSignedInProvider)) {
      try {
        final saved = await ref.read(trackRepositoryProvider).preferences();
        if (saved != null) {
          loaded = saved;
        } else if (guest.hasInterests) {
          await ref.read(trackRepositoryProvider).savePreferences(guest);
        }
      } catch (_) {
        // Keep what the browser knows; the screen still works.
      }
    }
    if (ref.mounted && generation == _generation) state = loaded;
  }

  Future<void> _save(UserPrefs next) async {
    state = next;
    final local = await _prefs();
    await local?.setStringList(_interestsKey, next.interests);
    if (ref.read(isSignedInProvider)) {
      await ref.read(trackRepositoryProvider).savePreferences(next);
    }
  }

  Future<void> setInterests(List<String> slugs) =>
      _save(state.copyWith(interests: slugs));
  Future<void> setPricingAlerts(bool on) =>
      _save(state.copyWith(pricingAlerts: on));
  Future<void> setRisingAlerts(bool on) =>
      _save(state.copyWith(risingAlerts: on));

  /// Whether to offer the interest picker now: once, after the second save,
  /// to someone who has not picked any — not as a wall before they start.
  Future<bool> shouldAskAfterSave(int savedCount) async {
    if (savedCount != 2 || state.hasInterests) return false;
    final local = await _prefs();
    if (local == null || local.getBool(_askedKey) == true) return false;
    await local.setBool(_askedKey, true);
    return true;
  }
}

final preferencesProvider = NotifierProvider<PreferencesController, UserPrefs>(
  PreferencesController.new,
);

/// The interest picker: the categories Liz has, as pills to tap.
Future<void> showInterestPicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: const _InterestPicker(),
    ),
  );
}

class _InterestPicker extends ConsumerStatefulWidget {
  const _InterestPicker();

  @override
  ConsumerState<_InterestPicker> createState() => _InterestPickerState();
}

class _InterestPickerState extends ConsumerState<_InterestPicker> {
  late final Set<String> _picked = ref
      .read(preferencesProvider)
      .interests
      .toSet();

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final categories = ref.watch(categoriesProvider).value ?? const [];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'What are you looking for?',
            style: LizText.title3.copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'Discover adds a shelf of what is rising in these. Change it any '
            'time in Settings.',
            style: LizText.callout.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in categories)
                LizFilterPill(
                  label: c.name,
                  selected: _picked.contains(c.slug),
                  onTap: () => setState(() {
                    if (!_picked.remove(c.slug)) _picked.add(c.slug);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            style: LizButtons.capsule,
            onPressed: () async {
              await ref
                  .read(preferencesProvider.notifier)
                  .setInterests(_picked.toList()..sort());
              if (context.mounted) Navigator.of(context).pop();
            },
            child: Text(_picked.isEmpty ? 'Not now' : 'Save'),
          ),
        ],
      ),
    );
  }
}
