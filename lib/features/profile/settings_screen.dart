import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/settings_controller.dart';
import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../core/providers.dart';
import '../../shared/widgets/grouped_list.dart';
import '../../shared/widgets/page_header.dart';
import '../auth/auth_controller.dart';

/// Settings as grouped lists (docs/DESIGN.md §8, Profile & Settings).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final signedIn = ref.watch(isSignedInProvider);
    final isLive = ref.watch(isLiveBackendProvider);
    final p = context.liz;
    final gutter = LizSpacing.gutter(MediaQuery.sizeOf(context).width);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: MaxWidth(
        maxWidth: 640 + gutter * 2,
        child: ListView(
          padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 40),
          children: [
            LizGroup(
              title: 'Appearance',
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Theme',
                          style: LizText.body.copyWith(color: p.textPrimary),
                        ),
                      ),
                      // Flexible gives the control a bounded width, so it
                      // scrolls on a narrow phone instead of overflowing.
                      Flexible(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: LizSegmented<ThemeMode>(
                            segments: const {
                              ThemeMode.system: 'System',
                              ThemeMode.light: 'Light',
                              ThemeMode.dark: 'Dark',
                            },
                            value: themeMode,
                            onChanged: (m) =>
                                ref.read(themeModeProvider.notifier).set(m),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            LizGroup(
              title: 'About',
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
                  iconColor: isLive ? p.positive : p.caution,
                  title: 'Backend',
                  value: isLive ? 'Connected' : 'Demo data',
                ),
              ],
            ),
            if (signedIn) ...[
              const SizedBox(height: 28),
              LizGroup(
                title: 'Account',
                footer:
                    'Deleting your account removes your profile, saves, '
                    'follows, reviews and posts. It cannot be undone.',
                children: [
                  LizGroupRow(
                    icon: Icons.logout,
                    iconColor: p.textSecondary,
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
            ],
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
