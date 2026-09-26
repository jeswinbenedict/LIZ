import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../core/repository/repositories.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/time_ago.dart';

final moderationReportsProvider = FutureProvider.autoDispose<List<ReportEntry>>(
  (ref) => ref.watch(adminRepositoryProvider).openReports(),
);

final hiddenContentProvider = FutureProvider.autoDispose<List<HiddenItem>>(
  (ref) => ref.watch(adminRepositoryProvider).hiddenContent(),
);

/// What readers flagged, and what is currently off the page.
///
/// The earlier version had three gaps that compounded. Its Hide button only
/// acted on posts; for a reported review or comment it quietly dismissed the
/// report instead, so a moderator could believe something was gone while it
/// stayed live. It showed a UUID in place of what had been reported. And the
/// report trigger could take things down on its own with no list anywhere of
/// what it had hidden, so a wrong call could never be reversed.
class ModerationTab extends ConsumerWidget {
  const ModerationTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(moderationReportsProvider);
    final hidden = ref.watch(hiddenContentProvider);

    return RefreshIndicator(
      onRefresh: () async => ref
        ..invalidate(moderationReportsProvider)
        ..invalidate(hiddenContentProvider),
      child: ListView(
        padding: const EdgeInsets.all(LizSpacing.md),
        children: [
          const _Heading(
            'Reported',
            'What readers flagged. Hiding takes it off the page and closes '
                'the report; dismissing leaves it up.',
          ),
          reports.when(
            loading: () => const LoadingView(),
            error: (_, _) => ErrorView(
              onRetry: () => ref.invalidate(moderationReportsProvider),
            ),
            data: (list) => list.isEmpty
                ? const _Quiet('Nothing reported.')
                : Column(
                    children: [for (final r in list) _ReportRow(report: r)],
                  ),
          ),
          const SizedBox(height: 28),
          const _Heading(
            'Hidden',
            'Off the page right now, by a moderator or because three '
                'established accounts reported it. Restore anything hidden '
                'by mistake.',
          ),
          hidden.when(
            loading: () => const LoadingView(),
            error: (_, _) =>
                ErrorView(onRetry: () => ref.invalidate(hiddenContentProvider)),
            data: (list) => list.isEmpty
                ? const _Quiet('Nothing hidden.')
                : Column(children: [for (final h in list) _HiddenRow(item: h)]),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.title, this.detail);
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            detail,
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Quiet extends StatelessWidget {
  const _Quiet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        text,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// A type label a moderator reads at a glance.
String _label(String type) => switch (type) {
  'post' => 'Post',
  'review' => 'Review',
  'comment' => 'Comment',
  'tool' => 'Tool',
  _ => type,
};

class _ReportRow extends ConsumerWidget {
  const _ReportRow({required this.report});
  final ReportEntry report;

  Future<void> _hide(BuildContext context, WidgetRef ref) async {
    final admin = ref.read(adminRepositoryProvider);
    await admin.setContentHidden(
      report.targetType,
      report.targetId,
      hidden: true,
    );
    await admin.resolveReport(report.id);
    ref
      ..invalidate(moderationReportsProvider)
      ..invalidate(hiddenContentProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('${_label(report.targetType)} hidden'),
          ),
        );
    }
  }

  Future<void> _dismiss(WidgetRef ref) async {
    await ref.read(adminRepositoryProvider).resolveReport(report.id);
    ref.invalidate(moderationReportsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final gone = report.preview.isEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flag_outlined, size: 18, color: scheme.error),
                const SizedBox(width: 6),
                Text(
                  _label(report.targetType),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${report.reason.isEmpty ? 'No reason given' : report.reason}'
                    ' · ${timeAgo(report.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // What was reported, so the decision can be made here rather than
            // after a trip to the database.
            Text(
              gone ? 'Already deleted by its author.' : report.preview,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontStyle: gone ? FontStyle.italic : null,
                color: gone ? scheme.onSurfaceVariant : null,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _dismiss(ref),
                  child: const Text('Dismiss'),
                ),
                const SizedBox(width: 4),
                // Nothing left to hide once the author deleted it.
                if (!gone)
                  FilledButton.tonal(
                    onPressed: () => _hide(context, ref),
                    child: Text(
                      'Hide ${_label(report.targetType).toLowerCase()}',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HiddenRow extends ConsumerWidget {
  const _HiddenRow({required this.item});
  final HiddenItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.visibility_off_outlined,
        color: scheme.onSurfaceVariant,
      ),
      title: Text(
        item.preview.isEmpty ? '(no text)' : item.preview,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${_label(item.targetType)} · ${timeAgo(item.createdAt)}',
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
      trailing: TextButton(
        onPressed: () async {
          await ref
              .read(adminRepositoryProvider)
              .setContentHidden(item.targetType, item.targetId, hidden: false);
          ref.invalidate(hiddenContentProvider);
        },
        child: const Text('Restore'),
      ),
    );
  }
}
