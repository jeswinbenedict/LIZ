import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/settings_controller.dart';
import '../../core/providers.dart';

/// Whether this browser has put the welcome card away. Kept in the browser
/// only: it is a convenience, and losing it costs one extra card.
class WelcomeDismissedController extends Notifier<bool> {
  static const _key = 'welcome_dismissed';
  SharedPreferences? _prefs;

  @override
  bool build() {
    _prefs = ref.watch(sharedPreferencesProvider).value;
    return _prefs?.getBool(_key) ?? false;
  }

  Future<void> dismiss() async {
    state = true;
    await _prefs?.setBool(_key, true);
  }
}

final welcomeDismissedProvider =
    NotifierProvider<WelcomeDismissedController, bool>(
      WelcomeDismissedController.new,
    );

/// What Liz is, for someone who arrived without knowing.
///
/// A first-time visitor lands on a grid of tools with no word on where they
/// come from or why an account would help, and the sign-in prompt only appears
/// once they tap something that needs it. This says it once, up front: what is
/// in the catalog, how to ask for something, and exactly what following a
/// tool gets you — the two alerts `on_tool_change_notify` actually sends, not a
/// vaguer promise. Hidden for anyone signed in, and for good once dismissed.
class WelcomeCard extends ConsumerWidget {
  const WelcomeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(isSignedInProvider) || ref.watch(welcomeDismissedProvider)) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Card(
        elevation: 0,
        color: scheme.primaryContainer.withValues(alpha: 0.45),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Semantics(
                        header: true,
                        child: Text(
                          'Find AI tools while they are still rising',
                          style: text.titleMedium,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Dismiss',
                    icon: const Icon(Icons.close, semanticLabel: 'Dismiss'),
                    onPressed: () =>
                        ref.read(welcomeDismissedProvider.notifier).dismiss(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const _Point(
                icon: Icons.trending_up,
                text:
                    'New launches from Product Hunt, Hacker News and GitHub, '
                    'checked and summarised every day.',
              ),
              const _Point(
                icon: Icons.auto_awesome_outlined,
                text:
                    'Ask Liz in plain words — "free tool to transcribe '
                    'meetings" — and get tools that fit.',
              ),
              const _Point(
                icon: Icons.notifications_none,
                text:
                    'Sign in and follow a tool to hear when its price changes '
                    'or it breaks into the top ten.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
