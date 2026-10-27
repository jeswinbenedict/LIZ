import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../core/repository/repositories.dart';
import '../../shared/widgets/equal_height_grid.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/time_ago.dart';
import 'admin_widgets.dart';

final healthProvider = FutureProvider.autoDispose<List<HealthSignal>>(
  (ref) => ref.watch(adminRepositoryProvider).health(),
);

final jobRunsProvider = FutureProvider.autoDispose<List<JobRun>>(
  (ref) => ref.watch(adminRepositoryProvider).recentJobRuns(),
);

final recentErrorsProvider = FutureProvider.autoDispose<List<ErrorGroup>>(
  (ref) => ref.watch(adminRepositoryProvider).recentErrors(),
);

final usageProvider = FutureProvider.autoDispose<Map<String, int>>(
  (ref) => ref.watch(adminRepositoryProvider).usageSummary(),
);

/// Whether the parts of Liz that run unattended are still working.
///
/// Everything here is derived from the data rather than from job logs. The
/// scheduled work fires an HTTP request and returns immediately, so a function
/// that fails on every call still leaves a job log saying the run succeeded.
/// If the catalog has not gained a tool in three days, something is broken
/// whatever the log says.
class HealthTab extends ConsumerWidget {
  const HealthTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(healthProvider);
    final gutter = LizSpacing.gutter(MediaQuery.sizeOf(context).width);

    return RefreshIndicator(
      onRefresh: () async {
        ref
          ..invalidate(healthProvider)
          ..invalidate(usageProvider)
          ..invalidate(jobRunsProvider)
          ..invalidate(recentErrorsProvider);
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(gutter, 24, gutter, 48),
        children: [
          health.when(
            loading: () => const LoadingView(),
            error: (_, _) => ErrorView(
              message: 'Health checks are visible to admins only.',
              onRetry: () => ref.invalidate(healthProvider),
            ),
            data: (signals) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Verdict(signals: signals),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, box) => EqualHeightGrid(
                    columns: box.maxWidth >= 900
                        ? 4
                        : box.maxWidth >= 480
                        ? 2
                        : 1,
                    children: [
                      for (final s in signals)
                        AdminStat(
                          label: _display(s.label),
                          value: s.value == s.value.roundToDouble()
                              ? s.value.toStringAsFixed(0)
                              : s.value.toStringAsFixed(1),
                          detail: s.detail,
                          status: adminStatusFrom(s.status),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const _JobRuns(),
          const _RecentErrors(),
          const _Usage(),
        ],
      ),
    );
  }
}

/// "ai summary coverage %" → "AI summary coverage %".
String _display(String label) => sentenceCase(
  label,
).replaceAll(RegExp(r'\bai\b', caseSensitive: false), 'AI');

/// One line at the top saying whether anything needs doing, so the panel can
/// be read at a glance rather than scanned.
class _Verdict extends StatelessWidget {
  const _Verdict({required this.signals});
  final List<HealthSignal> signals;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final failing = signals.where((s) => s.status == 'fail').length;
    final warning = signals.where((s) => s.status == 'warn').length;
    final status = failing > 0
        ? AdminStatus.failing
        : (warning > 0 ? AdminStatus.watch : AdminStatus.ok);

    final text = switch (status) {
      AdminStatus.failing =>
        '$failing signal${failing == 1 ? '' : 's'} failing — admins have been notified',
      AdminStatus.watch => '$warning to keep an eye on, nothing failing',
      _ => 'Everything is running',
    };
    final icon = switch (status) {
      AdminStatus.failing => Icons.error_outline,
      AdminStatus.watch => Icons.warning_amber_rounded,
      _ => Icons.check_circle_outline,
    };

    return AdminPanel(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: adminStatusColor(p, status)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: LizText.callout.copyWith(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The last week in numbers, from Liz's own event log — the first place to
/// look for whether anyone is using it, and where they stop.
class _Usage extends ConsumerWidget {
  const _Usage();

  /// The four that say most, as tiles; the rest as rows under them.
  static const _headline = [
    ('visitors', 'Visitors'),
    ('page_views', 'Pages viewed'),
    ('saves', 'Saves'),
    ('sign_ups', 'Sign-ups'),
  ];

  static const _rows = [
    ('returning_visitors', 'Came back on another day'),
    ('tool_views', 'Tool pages viewed'),
    ('website_visits', 'Sent to a tool\'s website'),
    ('searches', 'Searches and questions'),
    ('visitors_who_saved', 'Visitors who saved something'),
    ('came_back_this_week', 'Visited last week and again this week'),
    ('visitors_last_week', 'Visitors last week'),
    ('first_frame_ms_median', 'First screen, median (ms)'),
    ('first_frame_ms_p90', 'First screen, slowest 10% (ms)'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.liz;
    final usage = ref.watch(usageProvider);
    return AdminSection(
      title: 'Last 7 days',
      description:
          'Counted by Liz itself: a random id per browser, no cookies, no IP '
          'addresses kept.',
      child: usage.when(
        loading: () => const LoadingView(),
        error: (_, _) => const AdminPanel(
          children: [AdminEmpty('Usage could not be loaded.')],
        ),
        data: (m) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, box) => EqualHeightGrid(
                columns: box.maxWidth >= 900 ? 4 : 2,
                children: [
                  for (final (key, label) in _headline)
                    AdminStat(label: label, value: compactCount(m[key] ?? 0)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AdminPanel(
              children: [
                for (final (key, label) in _rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: LizText.callout.copyWith(
                              color: p.textSecondary,
                            ),
                          ),
                        ),
                        Text(
                          compactCount(m[key] ?? 0),
                          style: LizText.callout.copyWith(
                            color: p.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontFeatures: LizText.tabular,
                          ),
                        ),
                      ],
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

/// A row in a panel: a status icon, a line, and a line under it.
class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.status,
    required this.title,
    required this.detail,
    this.icon,
  });

  final AdminStatus status;
  final String title;
  final String detail;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              icon ??
                  (status == AdminStatus.ok
                      ? Icons.check_circle_outline
                      : Icons.error_outline),
              size: 18,
              color: adminStatusColor(p, status),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: LizText.callout.copyWith(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: LizText.footnote.copyWith(color: p.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JobRuns extends ConsumerWidget {
  const _JobRuns();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(jobRunsProvider);
    return AdminSection(
      title: 'Scheduled jobs',
      description:
          'Whether the attempt was made. The signals above say whether the '
          'work landed.',
      child: runs.when(
        loading: () => const LoadingView(),
        error: (_, _) => const SizedBox.shrink(),
        data: (list) => AdminPanel(
          children: list.isEmpty
              ? const [AdminEmpty('No runs recorded.')]
              : [
                  for (final run in list)
                    _StatusRow(
                      status: run.status == 'succeeded'
                          ? AdminStatus.ok
                          : AdminStatus.failing,
                      title: run.jobName,
                      detail:
                          '${timeAgo(run.startedAt)} ago · '
                          '${run.durationSeconds.toStringAsFixed(2)}s'
                          '${run.message.isEmpty ? '' : ' · ${run.message}'}',
                    ),
                ],
        ),
      ),
    );
  }
}

class _RecentErrors extends ConsumerWidget {
  const _RecentErrors();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final errors = ref.watch(recentErrorsProvider);
    return AdminSection(
      title: 'Crashes',
      description:
          'Grouped by fault, so one broken screen reads as a single problem '
          'with a count.',
      child: errors.when(
        loading: () => const LoadingView(),
        error: (_, _) => const SizedBox.shrink(),
        data: (list) => AdminPanel(
          children: list.isEmpty
              ? const [AdminEmpty('Nothing reported.')]
              : [
                  for (final e in list)
                    _StatusRow(
                      status: AdminStatus.failing,
                      icon: Icons.bug_report_outlined,
                      title: e.message,
                      detail:
                          '${e.occurrences}× · ${e.affectedUsers} affected · '
                          '${timeAgo(e.lastSeen)} ago'
                          '${e.route == null ? '' : ' · ${e.route}'}',
                    ),
                ],
        ),
      ),
    );
  }
}
