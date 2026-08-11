import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/breakpoints.dart';
import '../../core/providers.dart';
import '../../core/repository/repositories.dart';
import '../../shared/models/tool.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/time_ago.dart';
import '../../shared/widgets/tool_logo.dart';

final _allToolsProvider = FutureProvider<List<Tool>>(
    (ref) => ref.watch(adminRepositoryProvider).allTools());
final _reportsProvider = FutureProvider<List<ReportEntry>>(
    (ref) => ref.watch(adminRepositoryProvider).openReports());

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
              onPressed: () => context.go('/'), child: const Text('Go home')),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin console'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Content', icon: Icon(Icons.inventory_2_outlined)),
              Tab(text: 'Moderation', icon: Icon(Icons.flag_outlined)),
            ],
          ),
        ),
        body: MaxWidth(
          maxWidth: 1000,
          child: const TabBarView(
            children: [_ContentTab(), _ModerationTab()],
          ),
        ),
      ),
    );
  }
}

class _ContentTab extends ConsumerWidget {
  const _ContentTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tools = ref.watch(_allToolsProvider);
    final scheme = Theme.of(context).colorScheme;
    return tools.when(
      loading: () => const LoadingView(),
      error: (_, __) =>
          ErrorView(onRetry: () => ref.invalidate(_allToolsProvider)),
      data: (list) => ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: list.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final t = list[i];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 6),
            leading: ToolLogo(tool: t, size: 44),
            title: Text(t.name),
            subtitle: Text('${t.source ?? 'manual'} · ${t.category}',
                style: TextStyle(color: scheme.onSurfaceVariant)),
            trailing: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _StatusChip(status: t.status),
                PopupMenuButton<PublishStatus>(
                  onSelected: (s) async {
                    await ref
                        .read(adminRepositoryProvider)
                        .setToolStatus(t.id, s);
                    ref.invalidate(_allToolsProvider);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: PublishStatus.published, child: Text('Publish')),
                    PopupMenuItem(
                        value: PublishStatus.pending, child: Text('Mark pending')),
                    PopupMenuItem(
                        value: PublishStatus.hidden, child: Text('Hide')),
                  ],
                ),
              ],
            ),
          );
        },
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
              message: 'The moderation queue is clear.')
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
                      '${r.preview.isEmpty ? r.targetId : r.preview}\n${timeAgo(r.createdAt)} ago'),
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final PublishStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      PublishStatus.published => (Colors.green, 'Published'),
      PublishStatus.pending => (Colors.orange, 'Pending'),
      PublishStatus.hidden => (Colors.grey, 'Hidden'),
    };
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      visualDensity: VisualDensity.compact,
    );
  }
}
