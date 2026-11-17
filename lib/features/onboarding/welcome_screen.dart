import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/auth_gate.dart' show safeReturnPath, welcomePending;
import '../../app/responsive/adaptive_shell.dart' show LizWordmark;
import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../shared/widgets/grouped_list.dart';
import '../profile/preferences.dart';

/// The welcome a new account opens on (`/welcome`, docs/DESIGN.md §8): two
/// short steps — the kinds of tools you care about, then which alerts you
/// want — and then the page you were going to. Either step can be skipped;
/// both can be changed later in Settings.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key, this.returnTo});

  /// Where the visitor was going before they made an account.
  final String? returnTo;

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  static const _steps = 2;
  int _step = 0;
  bool _busy = false;
  late final Set<String> _picked = ref
      .read(preferencesProvider)
      .interests
      .toSet();
  late bool _pricing = ref.read(preferencesProvider).pricingAlerts;
  late bool _rising = ref.read(preferencesProvider).risingAlerts;

  /// Saves what was chosen, unless [save] is false (Skip), and moves on.
  Future<void> _finish({bool save = true}) async {
    setState(() => _busy = true);
    final prefs = ref.read(preferencesProvider.notifier);
    try {
      if (save) {
        await prefs.setInterests(_picked.toList()..sort());
        await prefs.setPricingAlerts(_pricing);
        await prefs.setRisingAlerts(_rising);
      }
      await prefs.markAsked();
    } catch (_) {
      // The choices are kept in the browser either way, and Settings can
      // change them; a failed save is no reason to hold someone here.
    }
    welcomePending.value = false;
    if (!mounted) return;
    context.go(safeReturnPath(widget.returnTo)?.toString() ?? '/');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final width = MediaQuery.sizeOf(context).width;
    final gutter = width >= 600 ? 32.0 : 20.0;
    final name = ref.watch(currentUserProvider)?.displayName.split(' ').first;

    final step = switch (_step) {
      0 => _StepBody(
        key: const ValueKey(0),
        title: name == null || name.isEmpty
            ? 'Welcome to Liz'
            : 'Welcome to Liz, $name',
        subtitle:
            'What are you looking for? Pick a few and Discover adds a shelf '
            'of what is rising in each.',
        child: InterestPills(
          picked: _picked,
          onToggle: (slug) => setState(() {
            if (!_picked.remove(slug)) _picked.add(slug);
          }),
        ),
      ),
      _ => _StepBody(
        key: const ValueKey(1),
        title: 'Hear when it matters',
        subtitle:
            'Save a tool and Liz tells you when it changes. Choose what is '
            'worth a notification.',
        child: LizGroup(
          children: [
            LizGroupSwitch(
              icon: Icons.sell_outlined,
              title: 'Price changes',
              subtitle: 'A plan is added, removed or repriced.',
              value: _pricing,
              onChanged: (v) => setState(() => _pricing = v),
            ),
            LizGroupSwitch(
              icon: Icons.trending_up,
              title: 'Rising into the top ten',
              subtitle: 'It breaks into this week’s top movers.',
              value: _rising,
              onChanged: (v) => setState(() => _rising = v),
            ),
          ],
        ),
      ),
    };

    final narrow = width < 600;
    Widget wrap(Widget button, {int flex = 1}) =>
        narrow ? Expanded(flex: flex, child: button) : button;
    final last = _step == _steps - 1;
    final primary = last
        ? 'Go to Discover'
        : _picked.isEmpty
        ? 'Skip this step'
        : 'Continue';

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The wordmark, and a way out for anyone who wants to look first.
            Padding(
              padding: EdgeInsets.fromLTRB(gutter, 10, gutter - 8, 10),
              child: Row(
                children: [
                  const LizWordmark(size: 24),
                  const Spacer(),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: p.textSecondary,
                    ),
                    onPressed: _busy ? null : () => _finish(save: false),
                    child: const Text('Skip'),
                  ),
                ],
              ),
            ),
            _Progress(step: _step, of: _steps),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      gutter,
                      width >= 600 ? 56 : 28,
                      gutter,
                      32,
                    ),
                    child: AnimatedSwitcher(
                      duration: LizMotion.of(context, LizMotion.standard),
                      child: step,
                    ),
                  ),
                ),
              ),
            ),
            // The step's buttons, along the foot.
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: p.hairline)),
              ),
              child: Align(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(gutter, 14, gutter, 14),
                    // On a phone the buttons share the width; wider, the
                    // primary one sits at the right.
                    child: Row(
                      children: [
                        if (_step > 0) ...[
                          wrap(
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 48),
                              ),
                              onPressed: _busy
                                  ? null
                                  : () => setState(() => _step--),
                              child: const Text('Back'),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        if (!narrow) const Spacer(),
                        wrap(
                          FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: Size(narrow ? 0 : 160, 48),
                            ),
                            onPressed: _busy
                                ? null
                                : last
                                ? _finish
                                : () => setState(() => _step++),
                            child: Text(primary, textAlign: TextAlign.center),
                          ),
                          flex: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A step: its title as the page's heading, one line, and its choices.
class _StepBody extends StatelessWidget {
  const _StepBody({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final phone = MediaQuery.sizeOf(context).width < 600;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          header: true,
          headingLevel: 1,
          child: Text(
            title,
            style: (phone ? LizText.title1 : LizText.largeTitle).copyWith(
              color: p.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(subtitle, style: LizText.body.copyWith(color: p.textSecondary)),
        const SizedBox(height: 28),
        child,
      ],
    );
  }
}

/// How far through the welcome: a segment per step, filled in ink up to the
/// current one, read out as "Step 1 of 2".
class _Progress extends StatelessWidget {
  const _Progress({required this.step, required this.of});
  final int step;
  final int of;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final duration = LizMotion.of(context, LizMotion.standard);
    return Semantics(
      label: 'Step ${step + 1} of $of',
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < of; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(
              child: AnimatedContainer(
                duration: duration,
                height: 2,
                color: i <= step ? p.textPrimary : p.hairline,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
