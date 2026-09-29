import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../core/repository/repositories.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/time_ago.dart';

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

    return RefreshIndicator(
      onRefresh: () async {
        ref
          ..invalidate(healthProvider)
          ..invalidate(usageProvider)
          ..invalidate(jobRunsProvider)
          ..invalidate(recentErrorsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(LizSpacing.md),
        children: [
          health.when(
            loading: () => const LoadingView(),
            error: (_, _) => ErrorView(
              message: 'Health checks are visible to admins only.',
              onRetry: () => ref.invalidate(healthProvider),
            ),
            data: (signals) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Verdict(signals: signals),
                const SizedBox(height: 12),
                for (final s in signals) _SignalTile(signal: s),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _JobRuns(),
          const SizedBox(height: 24),
          const _RecentErrors(),
          const SizedBox(height: 24),
          const _Usage(),
        ],
      ),
    );
  }
}

Color _colorFor(String status, ColorScheme scheme) => switch (status) {
  'fail' => scheme.error,
  'warn' => LizColors.rising,
  _ => LizColors.positive,
};

IconData _iconFor(String status) => switch (status) {
  'fail' => Icons.error_outline,
  'warn' => Icons.warning_amber_outlined,
  _ => Icons.check_circle_outline,
};

/// One line at the top saying whether anything needs doing, so the panel can
/// be read at a glance rather than scanned.
class _Verdict extends StatelessWidget {
  const _Verdict({required this.signals});
  final List<HealthSignal> signals;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final failing = signals.where((s) => s.status == 'fail').length;
    final warning = signals.where((s) => s.status == 'warn').length;
    final status = failing > 0 ? 'fail' : (warning > 0 ? 'warn' : 'ok');
    final colour = _colorFor(status, scheme);

    final text = switch (status) {
      'fail' =>
        '$failing signal${failing == 1 ? '' : 's'} failing — admins have been notified',
      'warn' => '$warning to keep an eye on, nothing failing',
      _ => 'Everything is running',
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(LizRadius.md),
      ),
      child: Row(
        children: [
          Icon(_iconFor(status), color: colour),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                // The status colour on a tint of itself: amber on pale amber
                // read at 2.25:1. Same hue, dark enough to read.
                color: LizColors.legibleOn(
                  colour,
                  Color.alphaBlend(
                    colour.withValues(alpha: 0.10),
                    scheme.surface,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalTile extends StatelessWidget {
  const _SignalTile({required this.signal});
  final HealthSignal signal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colour = _colorFor(signal.status, scheme);
    final value = signal.value == signal.value.roundToDouble()
        ? signal.value.toStringAsFixed(0)
        : signal.value.toStringAsFixed(1);

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(_iconFor(signal.status), color: colour, size: 20),
      title: Text(
        signal.label,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        signal.detail,
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
      trailing: Text(
        value,
        style: TextStyle(fontWeight: FontWeight.w700, color: colour),
      ),
    );
  }
}

/// The last week in numbers, from Liz's own event log — the first place to
/// look for whether anyone is using it, and where they stop.
class _Usage extends ConsumerWidget {
  const _Usage();

  static const _rows = [
    ('visitors', 'Visitors'),
    ('returning_visitors', 'Came back on another day'),
    ('page_views', 'Pages viewed'),
    ('tool_views', 'Tool pages viewed'),
    ('website_visits', 'Sent to a tool\'s website'),
    ('searches', 'Searches and questions'),
    ('saves', 'Saves'),
    ('visitors_who_saved', 'Visitors who saved something'),
    ('sign_ups', 'Sign-ups'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final usage = ref.watch(usageProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Last 7 days', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Counted by Liz itself: a random id per browser, no cookies, no IP '
          'addresses kept.',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        usage.when(
          loading: () => const LoadingView(),
          error: (_, _) => const SizedBox.shrink(),
          data: (m) => Column(
            children: [
              for (final (key, label) in _rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(child: Text(label)),
                      Text(
                        compactCount(m[key] ?? 0),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontFeatures: LizText.tabular,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _JobRuns extends ConsumerWidget {
  const _JobRuns();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final runs = ref.watch(jobRunsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Scheduled jobs', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Whether the attempt was made. The signals above say whether the '
          'work landed.',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        runs.when(
          loading: () => const LoadingView(),
          error: (_, _) => const SizedBox.shrink(),
          data: (list) => list.isEmpty
              ? Text(
                  'No runs recorded.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                )
              : Column(
                  children: [
                    for (final run in list)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          run.status == 'succeeded'
                              ? Icons.check_circle_outline
                              : Icons.error_outline,
                          size: 20,
                          color: run.status == 'succeeded'
                              ? LizColors.positive
                              : scheme.error,
                        ),
                        title: Text(run.jobName),
                        subtitle: Text(
                          '${timeAgo(run.startedAt)} · '
                          '${run.durationSeconds.toStringAsFixed(2)}s'
                          '${run.message.isEmpty ? '' : ' · ${run.message}'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
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

class _RecentErrors extends ConsumerWidget {
  const _RecentErrors();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final errors = ref.watch(recentErrorsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Crashes', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Grouped by fault, so one broken screen reads as a single problem '
          'with a count.',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        errors.when(
          loading: () => const LoadingView(),
          error: (_, _) => const SizedBox.shrink(),
          data: (list) => list.isEmpty
              ? Text(
                  'Nothing reported.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                )
              : Column(
                  children: [
                    for (final e in list)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.bug_report_outlined,
                          size: 20,
                          color: scheme.error,
                        ),
                        title: Text(
                          e.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${e.occurrences}× · ${e.affectedUsers} affected · '
                          '${timeAgo(e.lastSeen)}'
                          '${e.route == null ? '' : ' · ${e.route}'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
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
