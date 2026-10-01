import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/settings_controller.dart';
import '../../app/theme.dart';
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
    final p = context.liz;
    final gutter = LizSpacing.gutter(MediaQuery.sizeOf(context).width);
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 20, gutter, 0),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: p.surface,
          shape: LizRadius.shape(
            LizRadius.lg,
            side: BorderSide(color: p.hairline),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        'Find AI tools while they are still rising',
                        style: LizText.title3.copyWith(color: p.textPrimary),
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
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Three across when there is room; stacked on a phone.
                    if (constraints.maxWidth < 640) {
                      return const Column(
                        children: [
                          _PointHolder(0),
                          SizedBox(height: 14),
                          _PointHolder(1),
                          SizedBox(height: 14),
                          _PointHolder(2),
                        ],
                      );
                    }
                    return const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _PointHolder(0)),
                        SizedBox(width: 20),
                        Expanded(child: _PointHolder(1)),
                        SizedBox(width: 20),
                        Expanded(child: _PointHolder(2)),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The three points, by position, so both layouts above can be const.
class _PointHolder extends StatelessWidget {
  const _PointHolder(this.index);
  final int index;

  static const _points = [
    _Point(
      icon: Icons.trending_up,
      title: 'Early',
      text:
          'New launches from Product Hunt, Hacker News and GitHub, '
          'checked and summarised every day.',
    ),
    _Point(
      icon: Icons.auto_awesome_outlined,
      title: 'Plain words',
      text:
          'Ask Liz — "free tool to transcribe meetings" — and get tools '
          'that fit, with the reason why.',
    ),
    _Point(
      icon: Icons.notifications_none,
      title: 'Watched',
      text:
          'Save a tool to hear when its price changes or it breaks into the '
          'top ten.',
    ),
  ];

  @override
  Widget build(BuildContext context) => _points[index];
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: ShapeDecoration(
            color: p.accentSoft,
            shape: LizRadius.shape(9),
          ),
          child: Icon(icon, size: 18, color: p.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: LizText.headline.copyWith(color: p.textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                text,
                style: LizText.callout.copyWith(color: p.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
