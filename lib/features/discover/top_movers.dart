import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../core/ui_state.dart';
import '../../shared/models/tool.dart';
import '../../shared/models/tool_history.dart';
import '../../shared/widgets/badges.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/signal_sparkline.dart';
import '../../shared/widgets/tool_link.dart';
import '../../shared/widgets/tool_logo.dart';
import 'discover_controller.dart';

/// "Top movers": the tools growing fastest this week, as a ranked table —
/// Signal's centrepiece (docs/DESIGN.md §7, Movers table).
///
/// Only tools with measured growth appear (migration 0037), each with the
/// reason in words ("+1.2k GitHub stars this week") and its last two weeks as
/// a line. Wide layouts get a real table with column headings; phones get the
/// same facts as compact rows. The leader's row is lit.
/// What the movers table shows: everything (null), free tools ('free'), or
/// one kind of tool (its category slug).
final moversFilterProvider = uiStateProvider<String?>(null);

/// The filters offered: the kinds of tool that move most often.
const _moversFilters = <(String?, String)>[
  (null, 'All'),
  ('free', 'Free'),
  ('ai-agents', 'Agents'),
  ('ai-dev', 'Dev tools'),
  ('ai-research', 'Research'),
  ('ai-audio', 'Audio'),
  ('ai-video', 'Video'),
  ('ai-image', 'Image'),
];

class TopMovers extends ConsumerWidget {
  const TopMovers({super.key});

  /// Below this width the table's six columns no longer fit legibly.
  static const tableWidth = 760.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(moversFilterProvider);
    final key = FeedKey(
      sort: ToolSort.rising,
      pricing: filter == 'free'
          ? PricingType.free
          : ref.watch(discoverPricingProvider),
      category: filter == null || filter == 'free' ? null : filter,
      movingOnly: true,
    );
    final state = ref.watch(toolFeedProvider(key));
    // Nothing is moving at all: the section is absent. Nothing moving in
    // the chosen kind: the section stays, so the filter can be changed back.
    if (filter == null && (state.loading || state.items.isEmpty)) {
      return const SizedBox.shrink();
    }
    final p = context.liz;
    final gutter = LizSpacing.gutter(MediaQuery.sizeOf(context).width);
    final items = state.items.take(6).toList();
    // The lines arrive after the rows; the table never waits for them.
    final histories =
        ref
            .watch(_moversHistoryProvider(items.map((t) => t.id).join(',')))
            .value ??
        const <String, List<SignalPoint>>{};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          eyebrow: '// TOP MOVERS · 7 DAYS',
          title: 'Rising this week',
          subtitle:
              'Biggest jumps in the last seven days, on GitHub, '
              'Hacker News and Liz.',
        ),
        // Sideways on a narrow window rather than wrapping into rows.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 6),
          child: Row(
            children: [
              for (final (value, label) in _moversFilters) ...[
                LizFilterPill(
                  label: label,
                  selected: filter == value,
                  semanticLabel: 'Show $label movers',
                  onTap: () =>
                      ref.read(moversFilterProvider.notifier).set(value),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: items.isEmpty
              ? _NoMovers(loading: state.loading)
              : DecoratedBox(
                  decoration: ShapeDecoration(
                    color: p.surface,
                    shape: LizRadius.shape(
                      LizRadius.md,
                      side: BorderSide(color: p.hairline),
                    ),
                  ),
                  child: ClipRSuperellipse(
                    borderRadius: BorderRadius.circular(LizRadius.md),
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final wide = box.maxWidth >= tableWidth;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (wide) const _HeadingRow(),
                            for (var i = 0; i < items.length; i++) ...[
                              if (i > 0 || wide)
                                Divider(height: 1, color: p.hairline),
                              _MoverRow(
                                rank: i + 1,
                                tool: items[i],
                                history: histories[items[i].id] ?? const [],
                                wide: wide,
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// The chosen kind has nothing moving this week. Said plainly, in the
/// table's place, so the filter row above stays usable.
class _NoMovers extends StatelessWidget {
  const _NoMovers({required this.loading});
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Container(
      height: 96,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: p.surface,
        shape: LizRadius.shape(
          LizRadius.md,
          side: BorderSide(color: p.hairline),
        ),
      ),
      child: loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              'Nothing of this kind is rising this week.',
              style: LizText.callout.copyWith(color: p.textSecondary),
            ),
    );
  }
}

/// Two weeks of history for every row, in one request.
final _moversHistoryProvider = FutureProvider.autoDispose
    .family<Map<String, List<SignalPoint>>, String>(
      (ref, idsCsv) => ref
          .watch(contentRepositoryProvider)
          .signalHistories(idsCsv.split(',')),
    );

// The table's columns: fixed for figures, flexible for words.
const _rankW = 52.0;
const _signalW = 132.0;
const _priceW = 92.0;

class _HeadingRow extends StatelessWidget {
  const _HeadingRow();

  @override
  Widget build(BuildContext context) {
    final style = LizText.label.copyWith(color: context.liz.textSecondary);
    Widget cell(String text) => Text(text, style: style);
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Row(
          children: [
            SizedBox(width: _rankW, child: cell('RANK')),
            Expanded(flex: 5, child: cell('TOOL')),
            Expanded(flex: 6, child: cell('WHAT IT DOES')),
            SizedBox(width: _signalW, child: cell('14-DAY SIGNAL')),
            const SizedBox(width: 20),
            Expanded(flex: 4, child: cell('WHY IT’S RISING')),
            SizedBox(width: _priceW, child: cell('PRICE')),
          ],
        ),
      ),
    );
  }
}

class _MoverRow extends StatelessWidget {
  const _MoverRow({
    required this.rank,
    required this.tool,
    required this.history,
    required this.wide,
  });
  final int rank;
  final Tool tool;
  final List<SignalPoint> history;
  final bool wide;

  @override
  Widget build(BuildContext context) => ToolLink(tool: tool, builder: _row);

  Widget _row(BuildContext context, VoidCallback open) {
    final p = context.liz;
    final reason = tool.trendReason;
    final series = SignalSeries.pick(history);
    final leader = rank == 1;

    final rankText = Text(
      rank.toString().padLeft(2, '0'),
      style: LizText.mono.copyWith(
        fontSize: wide ? 15 : 14,
        color: rank <= 3 ? p.accent : p.textSecondary,
        shadows: leader ? [Shadow(color: p.glow, blurRadius: 8)] : null,
      ),
    );
    final reasonText = reason == null
        ? null
        : Text(
            reason,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: LizText.mono.copyWith(
              fontSize: wide ? 12.5 : 11.5,
              color: p.accent,
            ),
          );
    final spark = series == null
        ? null
        : SignalSparkline(
            values: series.values,
            semanticLabel: '${series.label}, last two weeks',
            width: wide ? 112 : 52,
            height: wide ? 30 : 22,
            strokeWidth: wide ? 1.6 : 1.4,
          );

    final Widget content = wide
        ? Row(
            children: [
              SizedBox(width: _rankW, child: rankText),
              Expanded(
                flex: 5,
                child: Row(
                  children: [
                    ToolLogo(tool: tool, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            tool.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: LizText.headline.copyWith(
                              color: p.textPrimary,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            categoryLabel(tool.category),
                            maxLines: 1,
                            style: LizText.footnote.copyWith(
                              color: p.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 6,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text(
                    tool.tagline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: LizText.callout.copyWith(color: p.textSecondary),
                  ),
                ),
              ),
              SizedBox(
                width: _signalW,
                child: Align(alignment: Alignment.centerLeft, child: spark),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: reasonText ?? const SizedBox.shrink(),
                ),
              ),
              SizedBox(
                width: _priceW,
                child: Text(
                  tool.pricingType == PricingType.unknown
                      ? '—'
                      : tool.pricingType.label,
                  style: LizText.footnote.copyWith(color: p.textSecondary),
                ),
              ),
            ],
          )
        : Row(
            children: [
              SizedBox(width: 30, child: rankText),
              ToolLogo(tool: tool, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tool.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LizText.headline.copyWith(color: p.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    reasonText ??
                        Text(
                          tool.tagline,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: LizText.subhead.copyWith(
                            color: p.textSecondary,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                  ],
                ),
              ),
              if (spark != null) ...[const SizedBox(width: 12), spark],
            ],
          );

    return Semantics(
      button: true,
      label:
          'Number $rank, ${tool.name}. ${tool.tagline}'
          '${reason == null ? '' : '. $reason'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: open,
        child: Container(
          constraints: BoxConstraints(minHeight: wide ? 68 : 64),
          padding: EdgeInsets.symmetric(
            horizontal: wide ? 20 : 14,
            vertical: 10,
          ),
          // The leader is lit: a red seam on its leading edge, and light
          // that fades across the row.
          decoration: leader
              ? BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      p.glow.withValues(alpha: 0.13),
                      p.glow.withValues(alpha: 0),
                    ],
                    stops: const [0, 0.6],
                  ),
                  border: Border(left: BorderSide(color: p.accent, width: 2)),
                )
              : null,
          alignment: Alignment.centerLeft,
          child: content,
        ),
      ),
    );
  }
}
