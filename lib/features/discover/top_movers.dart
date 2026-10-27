import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../core/ui_state.dart';
import '../../shared/models/tool.dart';
import '../../shared/models/tool_history.dart';
import '../../shared/widgets/pressable.dart';
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
  const TopMovers({super.key, this.category});

  /// Fixed to one category (a category page): no filter row.
  final String? category;

  /// Below this width the table's six columns no longer fit legibly.
  static const tableWidth = 760.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = category ?? ref.watch(moversFilterProvider);
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

    final filters = category == null
        ? Row(
            mainAxisSize: MainAxisSize.min,
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
          )
        : null;
    // From this width the filters fit beside the title.
    final besideTitle = MediaQuery.sizeOf(context).width >= 1280;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Rising this week',
          subtitle:
              'Biggest jumps in the last seven days, on GitHub, '
              'Hacker News and Liz.',
          action: besideTitle ? filters : null,
        ),
        // Sideways on a narrow window rather than wrapping into rows.
        if (filters != null && !besideTitle)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 6),
            child: filters,
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
const _priceW = 108.0;

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
            SizedBox(width: _rankW, child: cell('#')),
            Expanded(flex: 5, child: cell('Tool')),
            Expanded(flex: 6, child: cell('What it does')),
            SizedBox(width: _signalW, child: cell('Last 14 days')),
            const SizedBox(width: 20),
            Expanded(flex: 4, child: cell('Why it’s rising')),
            SizedBox(width: _priceW, child: cell('Price')),
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
    // The rank is a plain figure: the order is the data, the trend line and
    // the growth figure carry the colour.
    final rankText = Text(
      '$rank',
      style: LizText.mono.copyWith(
        fontSize: wide ? 14 : 13,
        color: p.textSecondary,
      ),
    );
    final reasonText = reason == null
        ? null
        : ReasonText(reason, maxLines: 2, small: !wide);
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
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: PricingLabel(tool.pricingType),
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

    // One sentence per part; taglines and reasons often bring their own
    // full stop, which a screen reader would otherwise read twice.
    String sentence(String s) => s.trim().replaceFirst(RegExp(r'[.!?]+$'), '');
    return Semantics(
      link: true,
      label: [
        'Number $rank, ${tool.name}',
        if (tool.tagline.trim().isNotEmpty) sentence(tool.tagline),
        if (reason != null && reason.trim().isNotEmpty) sentence(reason),
      ].join('. '),
      container: true,
      child: FocusOutline(
        builder: (context, onFocusChange) => InkWell(
          onTap: open,
          onFocusChange: onFocusChange,
          child: ExcludeSemantics(
            child: Container(
              constraints: BoxConstraints(minHeight: wide ? 68 : 64),
              padding: EdgeInsets.symmetric(
                horizontal: wide ? 20 : 14,
                vertical: 10,
              ),
              alignment: Alignment.centerLeft,
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

/// Why a tool is rising, with its growth figure in the accent and the words
/// in grey: "+2.2k GitHub stars this week" leads with "+2.2k". A reason that
/// does not start with a figure is grey throughout.
class ReasonText extends StatelessWidget {
  const ReasonText(
    this.reason, {
    super.key,
    this.maxLines = 2,
    this.small = false,
  });
  final String reason;
  final int maxLines;
  final bool small;

  static final _lead = RegExp(r'^([+\-−]?[\d.,]+\s?[kKmM%]?)\s+(.*)$');

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final base = (small ? LizText.footnote : LizText.subhead).copyWith(
      color: p.textSecondary,
      fontWeight: FontWeight.w400,
    );
    final m = _lead.firstMatch(reason.trim());
    return Text.rich(
      m == null
          ? TextSpan(text: reason)
          : TextSpan(
              children: [
                TextSpan(
                  text: m.group(1),
                  style: base.copyWith(
                    color: p.accent,
                    fontWeight: FontWeight.w600,
                    fontFeatures: LizText.tabular,
                  ),
                ),
                TextSpan(text: ' ${m.group(2)}'),
              ],
            ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: base,
    );
  }
}
