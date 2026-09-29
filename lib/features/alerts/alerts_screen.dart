import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../shared/models/app_notification.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/time_ago.dart';
import '../auth/sign_in_view.dart';
import 'alerts_controller.dart';

/// What happened while you were away, for the tools you saved.
class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(isSignedInProvider);
    final state = ref.watch(alertsControllerProvider);
    final controller = ref.read(alertsControllerProvider.notifier);

    final gutter = LizSpacing.gutter(MediaQuery.sizeOf(context).width);
    final p = context.liz;

    Widget body;
    if (!signedIn) {
      body = EmptyView(
        icon: Icons.notifications_none,
        title: 'Sign in to get alerts',
        message:
            'Save a tool and Liz tells you when its pricing changes '
            'or it starts rising.',
        action: FilledButton(
          onPressed: () => _promptSignIn(context),
          child: const Text('Sign in'),
        ),
      );
    } else if (state.loading) {
      body = const LoadingView();
    } else if (state.error != null && state.items.isEmpty) {
      body = ErrorView(onRetry: controller.refresh);
    } else if (state.items.isEmpty) {
      body = const EmptyView(
        icon: Icons.notifications_none,
        title: 'Nothing yet',
        message:
            'Save a tool from its page. When its pricing changes or '
            'it breaks into the top ten, it shows up here.',
      );
    } else {
      body = DecoratedBox(
        decoration: ShapeDecoration(
          color: p.surface,
          shape: LizRadius.shape(
            LizRadius.md,
            side: BorderSide(color: p.hairline),
          ),
        ),
        child: ClipRSuperellipse(
          borderRadius: BorderRadius.circular(LizRadius.md),
          child: Column(
            children: [
              for (var i = 0; i < state.items.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 68),
                    child: Divider(height: 1, color: p.hairline),
                  ),
                _AlertTile(
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
              ],
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: MaxWidth(
          maxWidth: 760 + gutter * 2,
          child: ListView(
            padding: EdgeInsets.fromLTRB(0, 0, 0, 40),
            children: [
              PageHeader(
                title: 'Alerts',
                subtitle: signedIn
                    ? 'Price changes and rises, for the tools you saved.'
                    : null,
                trailing: signedIn && state.unread > 0
                    ? TextButton(
                        onPressed: controller.markAllRead,
                        child: const Text('Mark all read'),
                      )
                    : null,
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                child: body,
              ),
            ],
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
    final p = context.liz;
    final icon = _icons[alert.type] ?? Icons.notifications_none;
    final unread = !alert.read;

    return Semantics(
      button: true,
      label:
          '${unread ? 'Unread. ' : ''}${alert.title}. ${alert.body}. '
          '${timeAgo(alert.createdAt)} ago',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: ShapeDecoration(
                  color: unread ? p.accentSoft : p.surfaceMuted,
                  shape: LizRadius.shape(10),
                ),
                child: Icon(
                  icon,
                  size: 19,
                  color: unread ? p.accent : p.textSecondary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            alert.title,
                            style: LizText.headline.copyWith(
                              color: p.textPrimary,
                              fontWeight: unread
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        Text(
                          timeAgo(alert.createdAt),
                          style: LizText.footnote.copyWith(
                            color: p.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    if (alert.body.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        alert.body,
                        style: LizText.callout.copyWith(color: p.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Unread is a dot, like Mail: the row stays quiet, the dot
              // says what is new.
              SizedBox(
                width: 10,
                child: unread
                    ? Container(
                        width: 9,
                        height: 9,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(
                          color: p.accent,
                          shape: BoxShape.circle,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
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
