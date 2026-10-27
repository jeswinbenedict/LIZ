import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../core/providers.dart';
import '../../shared/widgets/grouped_list.dart';
import '../auth/auth_controller.dart';
import 'data_export.dart';
import 'preferences.dart';
import '../../shared/widgets/top_bar.dart';

/// Settings as grouped lists (docs/DESIGN.md §8, Profile & Settings).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(isSignedInProvider);
    final isLive = ref.watch(isLiveBackendProvider);
    final prefs = ref.watch(preferencesProvider);
    final p = context.liz;
    final gutter = LizSpacing.gutter(MediaQuery.sizeOf(context).width);
    final phone = context.isPhone;

    return Scaffold(
      // The page's heading is the title below the bar.
      appBar: const LizTopBar(
        title: 'Settings',
        section: ('Profile', '/profile'),
        fallback: '/profile',
        titleIsHeading: false,
      ),
      body: MaxWidth(
        maxWidth: 920 + gutter * 2,
        child: ListView(
          padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 40),
          children: [
            Padding(
              padding: EdgeInsets.only(top: phone ? 8 : 36, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    container: true,
                    header: true,
                    headingLevel: 1,
                    child: Text(
                      'Settings',
                      style: (phone ? LizText.title1 : LizText.largeTitle)
                          .copyWith(color: p.textPrimary),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'What Liz shows you, what it tells you about, and your '
                    'account.',
                    style: LizText.body.copyWith(color: p.textSecondary),
                  ),
                ],
              ),
            ),
            _Section(
              title: 'Discover',
              description: 'Liz puts tools in these categories first.',
              children: [
                LizGroupRow(
                  icon: Icons.interests_outlined,
                  title: 'Your interests',
                  value: prefs.hasInterests
                      ? '${prefs.interests.length} chosen'
                      : 'None',
                  onTap: () => showInterestPicker(context),
                ),
              ],
            ),
            if (signedIn)
              _Section(
                title: 'Alerts for saved tools',
                description:
                    'What Liz tells you about the tools you saved. Alerts '
                    'appear under the bell.',
                children: [
                  _SwitchRow(
                    icon: Icons.sell_outlined,
                    title: 'Price changes',
                    subtitle: 'A plan is added, removed or repriced.',
                    value: prefs.pricingAlerts,
                    onChanged: (v) => ref
                        .read(preferencesProvider.notifier)
                        .setPricingAlerts(v),
                  ),
                  _SwitchRow(
                    icon: Icons.trending_up,
                    title: 'Rising into the top ten',
                    subtitle: 'It breaks into this week\u2019s top movers.',
                    value: prefs.risingAlerts,
                    onChanged: (v) => ref
                        .read(preferencesProvider.notifier)
                        .setRisingAlerts(v),
                  ),
                ],
              ),
            _Section(
              title: 'About',
              description:
                  'The small print, and where Liz\u2019s data comes '
                  'from.',
              children: [
                LizGroupRow(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy policy',
                  onTap: () => context.push('/privacy'),
                ),
                LizGroupRow(
                  icon: Icons.description_outlined,
                  title: 'Terms of service',
                  onTap: () => context.push('/terms'),
                ),
                LizGroupRow(
                  icon: Icons.cloud_outlined,
                  title: 'Backend',
                  value: isLive ? 'Connected' : 'Demo data',
                ),
              ],
            ),
            if (signedIn)
              _Section(
                title: 'Account',
                description: 'Your data is yours: take a copy, or remove it.',
                footer:
                    'Deleting your account removes your profile, saves, '
                    'follows, reviews and posts. It cannot be undone.',
                children: [
                  LizGroupRow(
                    icon: Icons.download_outlined,
                    title: 'Download my data',
                    subtitle: 'Everything you added, as a JSON file.',
                    showChevron: false,
                    onTap: () => _export(context, ref),
                  ),
                  LizGroupRow(
                    icon: Icons.logout,
                    title: 'Sign out',
                    showChevron: false,
                    onTap: () async {
                      await ref.read(authControllerProvider.notifier).signOut();
                      if (context.mounted) context.go('/');
                    },
                  ),
                  LizGroupRow(
                    icon: Icons.delete_forever_outlined,
                    title: 'Delete account',
                    destructive: true,
                    showChevron: false,
                    onTap: () => _confirmDelete(context, ref),
                  ),
                ],
              ),
            const SizedBox(height: 32),
            Center(
              child: Text(
                'Liz 1.0',
                style: LizText.footnote.copyWith(color: p.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await ref.read(exportMyDataProvider)();
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              saved
                  ? 'Your data was downloaded as a JSON file.'
                  : 'Downloading is only available in the browser.',
            ),
          ),
        );
    } catch (_) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text("We couldn't put your data together. Try again."),
          ),
        );
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently deletes your account, posts, and reviews. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // The actual deletion is performed server-side (Edge Function) using the
    // service role; here we request it and sign out.
    try {
      await ref.read(authRepositoryProvider).deleteAccount();
    } catch (error) {
      // Never leave on the happy path after a failed erasure: the user would
      // believe their account and data were gone when nothing was removed.
      if (!context.mounted) return;
      final message = error is LizException
          ? error.message
          : "We couldn't delete your account. Please try again.";
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    if (context.mounted) context.go('/');
  }
}

/// One block of settings. Wide: the name and what it is for in a column on
/// the left, the rows on the right — the way Linear and Vercel lay out
/// settings. Narrow: the name and sentence above the rows.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.description,
    required this.children,
    this.footer,
  });

  final String title;
  final String description;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          container: true,
          header: true,
          child: Text(
            title,
            style: LizText.headline.copyWith(color: p.textPrimary),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: LizText.footnote.copyWith(color: p.textSecondary),
        ),
      ],
    );
    final group = LizGroup(footer: footer, children: children);
    return Padding(
      padding: EdgeInsets.only(top: wide ? 32 : 28),
      child: wide
          ? Column(
              children: [
                Divider(height: 1, color: p.hairline),
                const SizedBox(height: 32),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 260, child: label),
                    const SizedBox(width: 40),
                    Expanded(child: group),
                  ],
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: label,
                ),
                group,
              ],
            ),
    );
  }
}

/// A grouped-list row with a switch, at the same height and spacing as
/// LizGroupRow.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    // Its own transparent Material: the group behind it is a coloured box,
    // which would otherwise hide the row's ink.
    return Material(
      type: MaterialType.transparency,
      child: MergeSemantics(
        child: SwitchListTile(
          // The same icon tile and insets as LizGroupRow, so the hairlines
          // between rows line up.
          contentPadding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
          horizontalTitleGap: 14,
          secondary: Container(
            width: 30,
            height: 30,
            decoration: ShapeDecoration(
              color: p.surfaceHover,
              shape: LizRadius.shape(
                LizRadius.sm,
                side: BorderSide(color: p.hairlineStrong),
              ),
            ),
            child: Icon(icon, size: 17, color: p.textPrimary),
          ),
          title: Text(
            title,
            style: LizText.body.copyWith(color: p.textPrimary),
          ),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle!,
                  style: LizText.footnote.copyWith(color: p.textSecondary),
                ),
          value: value,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
