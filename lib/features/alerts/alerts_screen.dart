import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../shared/models/app_notification.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/time_ago.dart';
import '../auth/sign_in_view.dart';
import 'alerts_controller.dart';

/// What happened while you were away, for the tools you follow.
class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(isSignedInProvider);
    final state = ref.watch(alertsControllerProvider);
    final controller = ref.read(alertsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        actions: [
          if (signedIn && state.unread > 0)
            TextButton(
              onPressed: controller.markAllRead,
              child: const Text('Mark all read'),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: MaxWidth(
        maxWidth: 760,
        child: !signedIn
            ? EmptyView(
                icon: Icons.notifications_none,
                title: 'Sign in to get alerts',
                message:
                    'Follow a tool and Liz tells you when its pricing changes '
                    'or it starts climbing.',
                action: FilledButton(
                  onPressed: () => _promptSignIn(context),
                  child: const Text('Sign in'),
                ),
              )
            : state.loading
            ? const LoadingView()
            : state.error != null && state.items.isEmpty
            ? ErrorView(onRetry: controller.refresh)
            : state.items.isEmpty
            ? const EmptyView(
                icon: Icons.notifications_none,
                title: 'Nothing yet',
                message:
                    'Follow a tool from its page. When its pricing changes or '
                    'it breaks into the top ten, it shows up here.',
              )
            : RefreshIndicator(
                onRefresh: controller.refresh,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: state.items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _AlertTile(
                    alert: state.items[i],
                    onTap: () {
                      final alert = state.items[i];
                      controller.markRead(alert);
                      final route = alert.route;
                      if (route != null && route.isNotEmpty) {
                        context.push(route);
                      }
                    },
                  ),
                ),
              ),
      ),
    );
  }
}

void _promptSignIn(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: SignInView(onSignedIn: () => Navigator.of(ctx).pop()),
    ),
  );
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert, required this.onTap});
  final AppNotification alert;
  final VoidCallback onTap;

  /// The icon says what kind of change this was before the words are read.
  static const _icons = <String, IconData>{
    'pricing': Icons.sell_outlined,
    'trending': Icons.trending_up,
    'comment': Icons.mode_comment_outlined,
    'follow': Icons.person_add_alt,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = _icons[alert.type] ?? Icons.notifications_none;

    return ListTile(
      onTap: onTap,
      // An unread alert is tinted rather than badged: the whole row reads as
      // new, which survives being glanced at on a phone.
      tileColor: alert.read ? null : scheme.primary.withValues(alpha: 0.05),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: LizSpacing.md,
        vertical: 6,
      ),
      leading: CircleAvatar(
        backgroundColor: alert.read
            ? scheme.surfaceContainerHighest
            : scheme.primary.withValues(alpha: 0.14),
        child: Icon(
          icon,
          size: 20,
          color: alert.read ? scheme.onSurfaceVariant : scheme.primary,
        ),
      ),
      title: Text(
        alert.title,
        style: TextStyle(
          fontWeight: alert.read ? FontWeight.w500 : FontWeight.w700,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (alert.body.isNotEmpty) Text(alert.body),
          const SizedBox(height: 2),
          Text(
            timeAgo(alert.createdAt),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
      trailing: alert.route == null
          ? null
          : Icon(Icons.chevron_right, color: scheme.onSurfaceVariant, size: 20),
    );
  }
}

/// The bell, with a count of what is waiting. Hidden entirely for a guest —
/// an empty bell invites a tap that only leads to a sign-in wall.
class AlertsBell extends ConsumerWidget {
  const AlertsBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isSignedInProvider)) return const SizedBox.shrink();
    final unread = ref.watch(unreadAlertsProvider);

    return IconButton(
      tooltip: unread == 0 ? 'Alerts' : '$unread unread alerts',
      onPressed: () => context.push('/alerts'),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 9 ? '9+' : '$unread'),
        child: Icon(
          unread > 0 ? Icons.notifications : Icons.notifications_none,
        ),
      ),
    );
  }
}
