import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/settings_controller.dart';
import '../../core/errors.dart';
import '../../core/providers.dart';
import '../auth/auth_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final signedIn = ref.watch(isSignedInProvider);
    final isLive = ref.watch(isLiveBackendProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: MaxWidth(
        maxWidth: 640,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            const _SectionLabel('Appearance'),
            RadioListTile<ThemeMode>(
              title: const Text('System'),
              value: ThemeMode.system,
              groupValue: themeMode,
              onChanged: (m) => ref.read(themeModeProvider.notifier).set(m!),
            ),
            RadioListTile<ThemeMode>(
              title: const Text('Light'),
              value: ThemeMode.light,
              groupValue: themeMode,
              onChanged: (m) => ref.read(themeModeProvider.notifier).set(m!),
            ),
            RadioListTile<ThemeMode>(
              title: const Text('Dark'),
              value: ThemeMode.dark,
              groupValue: themeMode,
              onChanged: (m) => ref.read(themeModeProvider.notifier).set(m!),
            ),
            const Divider(),
            const _SectionLabel('About'),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy policy'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/privacy'),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Terms of service'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/terms'),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Backend'),
              subtitle: Text(isLive
                  ? 'Connected to Supabase'
                  : 'Demo mode (bundled sample data)'),
            ),
            if (signedIn) ...[
              const Divider(),
              const _SectionLabel('Account'),
              ListTile(
                leading: Icon(Icons.logout, color: scheme.error),
                title: Text('Sign out', style: TextStyle(color: scheme.error)),
                onTap: () async {
                  await ref.read(authControllerProvider.notifier).signOut();
                  if (context.mounted) context.go('/');
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_forever_outlined, color: scheme.error),
                title: const Text('Delete account'),
                subtitle: const Text('Permanently remove your account and data'),
                onTap: () => _confirmDelete(context, ref),
              ),
            ],
            const SizedBox(height: 24),
            Center(
              child: Text('Liz v1.0.0',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
            const SizedBox(height: 24),
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
            'This permanently deletes your account, posts, and reviews. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(text.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: Theme.of(context).colorScheme.primary,
          )),
    );
  }
}
