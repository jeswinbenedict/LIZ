import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../core/repository/repositories.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/time_ago.dart';
import 'admin_widgets.dart';

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

    final gutter = LizSpacing.gutter(MediaQuery.sizeOf(context).width);
    return RefreshIndicator(
      onRefresh: () async => ref
        ..invalidate(moderationReportsProvider)
        ..invalidate(hiddenContentProvider),
      child: ListView(
        padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 48),
        children: [
          AdminSection(
            top: 24,
            title: 'Reported',
            description:
                'What readers flagged. Hiding takes it off the page and closes '
                'the report; dismissing leaves it up.',
            child: reports.when(
              loading: () => const LoadingView(),
              error: (_, _) => ErrorView(
                onRetry: () => ref.invalidate(moderationReportsProvider),
              ),
              data: (list) => AdminPanel(
                children: list.isEmpty
                    ? const [AdminEmpty('Nothing reported.')]
                    : [for (final r in list) _ReportRow(report: r)],
              ),
            ),
          ),
          AdminSection(
            title: 'Hidden',
            description:
                'Off the page right now, by a moderator or because three '
                'established accounts reported it. Restore anything hidden '
                'by mistake.',
            child: hidden.when(
              loading: () => const LoadingView(),
              error: (_, _) => ErrorView(
                onRetry: () => ref.invalidate(hiddenContentProvider),
              ),
              data: (list) => AdminPanel(
                children: list.isEmpty
                    ? const [AdminEmpty('Nothing hidden.')]
                    : [for (final h in list) _HiddenRow(item: h)],
              ),
            ),
          ),
        ],
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
    final p = context.liz;
    final gone = report.preview.isEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_outlined, size: 16, color: LizColors.warn),
              const SizedBox(width: 8),
              Text(
                _label(report.targetType),
                style: LizText.callout.copyWith(
                  color: p.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${report.reason.isEmpty ? 'No reason given' : report.reason}'
                  ' · ${timeAgo(report.createdAt)} ago',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LizText.footnote.copyWith(color: p.textSecondary),
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
            style: LizText.callout.copyWith(
              color: gone ? p.textSecondary : p.textPrimary,
              fontStyle: gone ? FontStyle.italic : null,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: () => _dismiss(ref),
                child: const Text('Dismiss'),
              ),
              const SizedBox(width: 8),
              // Nothing left to hide once the author deleted it.
              if (!gone)
                FilledButton(
                  onPressed: () => _hide(context, ref),
                  child: Text(
                    'Hide ${_label(report.targetType).toLowerCase()}',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HiddenRow extends ConsumerWidget {
  const _HiddenRow({required this.item});
  final HiddenItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.liz;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          Icon(Icons.visibility_off_outlined, size: 18, color: p.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.preview.isEmpty ? '(no text)' : item.preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: LizText.callout.copyWith(color: p.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_label(item.targetType)} · ${timeAgo(item.createdAt)} ago',
                  style: LizText.footnote.copyWith(color: p.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: () async {
              await ref
                  .read(adminRepositoryProvider)
                  .setContentHidden(
                    item.targetType,
                    item.targetId,
                    hidden: false,
                  );
              ref.invalidate(hiddenContentProvider);
            },
            child: const Text('Restore'),
          ),
        ],
      ),
    );
  }
}
