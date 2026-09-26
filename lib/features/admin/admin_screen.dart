import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/breakpoints.dart';
import '../../core/providers.dart';
import '../../core/repository/repositories.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/time_ago.dart';
import 'content_tab.dart';
import 'health_tab.dart';

final _reportsProvider = FutureProvider<List<ReportEntry>>(
  (ref) => ref.watch(adminRepositoryProvider).openReports(),
);

/// Web-focused moderation console. Role-gated: non-admins are turned away
/// (defense-in-depth on top of RLS, which is the real enforcement).
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProvider);
    if (profile == null || !profile.role.canModerate) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin')),
        body: EmptyView(
          icon: Icons.lock_outline,
          title: 'Admins only',
          message: 'You don\'t have permission to view this page.',
          action: FilledButton(
            onPressed: () => context.go('/'),
            child: const Text('Go home'),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin console'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Health', icon: Icon(Icons.monitor_heart_outlined)),
              Tab(text: 'Content', icon: Icon(Icons.inventory_2_outlined)),
              Tab(text: 'Moderation', icon: Icon(Icons.flag_outlined)),
            ],
          ),
        ),
        body: MaxWidth(
          maxWidth: 1000,
          child: const TabBarView(
            children: [HealthTab(), ContentTab(), _ModerationTab()],
          ),
        ),
      ),
    );
  }
}

class _ModerationTab extends ConsumerWidget {
  const _ModerationTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(_reportsProvider);
    return reports.when(
      loading: () => const LoadingView(),
      error: (_, __) =>
          ErrorView(onRetry: () => ref.invalidate(_reportsProvider)),
      data: (list) => list.isEmpty
          ? const EmptyView(
              icon: Icons.verified_outlined,
              title: 'Nothing to review',
              message: 'The moderation queue is clear.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final r = list[i];
                return ListTile(
                  leading: const Icon(Icons.flag, color: Colors.redAccent),
                  title: Text('${r.targetType} · ${r.reason}'),
                  subtitle: Text(
                    '${r.preview.isEmpty ? r.targetId : r.preview}\n${timeAgo(r.createdAt)} ago',
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Hide content',
                        icon: const Icon(Icons.visibility_off_outlined),
                        onPressed: () async {
                          if (r.targetType == 'post') {
                            await ref
                                .read(adminRepositoryProvider)
                                .setPostStatus(r.targetId, 'hidden');
                          }
                          await ref
                              .read(adminRepositoryProvider)
                              .resolveReport(r.id);
                          ref.invalidate(_reportsProvider);
                        },
                      ),
                      IconButton(
                        tooltip: 'Dismiss report',
                        icon: const Icon(Icons.check),
                        onPressed: () async {
                          await ref
                              .read(adminRepositoryProvider)
                              .resolveReport(r.id);
                          ref.invalidate(_reportsProvider);
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
