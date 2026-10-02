import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../shared/models/tool.dart';
import '../../shared/models/tool_history.dart';
import '../../shared/widgets/signal_sparkline.dart';
import '../../shared/widgets/time_ago.dart';

final signalHistoryProvider = FutureProvider.autoDispose
    .family<List<SignalPoint>, String>(
      (ref, toolId) =>
          ref.watch(contentRepositoryProvider).signalHistory(toolId),
    );

final toolChangesProvider = FutureProvider.autoDispose
    .family<List<ToolChange>, String>(
      (ref, toolId) => ref.watch(contentRepositoryProvider).toolChanges(toolId),
    );

/// The date history begins: nothing before it was measured.
final historyStart = DateTime.utc(2026, 9, 29);

Widget _heading(BuildContext context, String title) {
  final p = context.liz;
  return Semantics(
    container: true,
    header: true,
    child: Text(title, style: LizText.title2.copyWith(color: p.textPrimary)),
  );
}

/// How the tool's main signal moved over the last 30 days, as a signal line
/// with the numbers in words. Until there are three days of history it says
/// so, rather than drawing a line out of one point.
class ToolSignalsSection extends ConsumerWidget {
  const ToolSignalsSection({super.key, required this.tool});
  final Tool tool;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final points = ref.watch(signalHistoryProvider(tool.id)).value;
    if (points == null || points.isEmpty) return const SizedBox.shrink();
    final p = context.liz;
    final series = SignalSeries.pick(points);
    final since = DateFormat('d MMM').format(points.first.day);

    // An instrument panel: Signal's signature on a tool page. A seam of red
    // light along its top, the label and the reason in monospace, the line.
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: p.surface,
          shape: LizRadius.shape(
            LizRadius.md,
            side: BorderSide(color: p.hairline),
          ),
        ),
        child: Stack(
          children: [
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: GlowLine(strength: 0.8),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        container: true,
                        header: true,
                        child: Text(
                          'SIGNAL · ${points.length} DAYS',
                          style: LizText.label.copyWith(color: p.textSecondary),
                        ),
                      ),
                      const SizedBox(width: 16),
                      if (tool.trendReason != null)
                        Expanded(
                          child: Text(
                            tool.trendReason!,
                            textAlign: TextAlign.end,
                            style: LizText.mono.copyWith(
                              fontSize: 12,
                              color: p.accent,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // The body is its own node: the heading is read first,
                  // then what it heads, not the text as a group label.
                  if (series == null)
                    Semantics(
                      container: true,
                      child: Text(
                        'Liz has recorded this tool\'s signals daily since '
                        '$since. Nothing measurable has moved yet; the line '
                        'appears once it does.',
                        style: LizText.callout.copyWith(color: p.textSecondary),
                      ),
                    )
                  else
                    Semantics(
                      container: true,
                      child: LayoutBuilder(
                        builder: (context, box) {
                          final change = series.last - series.first;
                          final summary =
                              '${series.label}: ${_fmt(series.first)} → '
                              '${_fmt(series.last)} since $since';
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SignalSparkline(
                                values: series.values,
                                width: box.maxWidth,
                                height: 76,
                                strokeWidth: 2,
                                semanticLabel: summary,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                summary,
                                style: LizText.mono.copyWith(
                                  fontSize: 12,
                                  color: p.textPrimary,
                                ),
                              ),
                              if (change > 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    '+${_fmt(change)} in ${points.length - 1} '
                                    '${points.length == 2 ? 'day' : 'days'}',
                                    style: LizText.mono.copyWith(
                                      fontSize: 12,
                                      color: p.accent,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? compactCount(v.round()) : v.toStringAsFixed(1);
}

/// What happened to the tool, newest first: price changes as they were
/// recorded, its Hacker News launch, and when Liz first saw it. The tool's
/// story, from facts Liz holds.
class ToolTimelineSection extends ConsumerWidget {
  const ToolTimelineSection({super.key, required this.tool});
  final Tool tool;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final changes = ref.watch(toolChangesProvider(tool.id)).value ?? const [];
    final events = <_Event>[
      for (final c in changes)
        _Event(
          c.changedAt,
          Icons.sell_outlined,
          c.field == 'pricing_type'
              ? 'Pricing changed: ${_label(c.oldValue)} → ${_label(c.newValue)}'
              : 'Price updated: ${c.newValue ?? 'removed'}',
        ),
      if (tool.hnPostedAt != null)
        _Event(
          tool.hnPostedAt!,
          Icons.forum_outlined,
          tool.hnPoints == null
              ? 'Launched on Hacker News'
              : 'Launched on Hacker News · ${compactCount(tool.hnPoints!)} '
                    'points',
        ),
      _Event(tool.createdAt, Icons.visibility_outlined, 'First seen by Liz'),
    ]..sort((a, b) => b.at.compareTo(a.at));

    final p = context.liz;
    return Padding(
      padding: const EdgeInsets.only(top: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(context, 'Timeline'),
          const SizedBox(height: 14),
          for (var i = 0; i < events.length; i++)
            _TimelineRow(event: events[i], last: i == events.length - 1),
          if (changes.isEmpty && tool.createdAt.isBefore(historyStart))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Price changes are recorded from 29 September 2026.',
                style: LizText.footnote.copyWith(color: p.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  static String _label(String? v) => switch (v) {
    'free' => 'Free',
    'freemium' => 'Freemium',
    'paid' => 'Paid',
    _ => 'Unknown',
  };
}

class _Event {
  const _Event(this.at, this.icon, this.text);
  final DateTime at;
  final IconData icon;
  final String text;
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.event, required this.last});
  final _Event event;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Icon(event.icon, size: 18, color: p.accent),
                if (!last)
                  Expanded(
                    child: Center(
                      child: Container(width: 1.5, color: p.hairline),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.text,
                    style: LizText.callout.copyWith(color: p.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('d MMM y').format(event.at.toLocal()),
                    style: LizText.footnote.copyWith(
                      color: p.textSecondary,
                      fontFeatures: LizText.tabular,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
