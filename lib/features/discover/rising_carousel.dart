import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../core/repository/repositories.dart';
import '../../shared/models/tool.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/tool_link.dart';
import '../../shared/widgets/tool_logo.dart';
import 'discover_controller.dart';

/// "Rising this week" as a chart: rank numerals, logo, name, and what moved —
/// the App Store's Top Charts pattern (docs/DESIGN.md §7, Chart row).
///
/// Only tools with measured growth appear (migration 0037), each with the
/// reason in words: "+1.2k GitHub stars this week", "227 points on Hacker
/// News". It used to rank the most famous tools by seeded totals under the
/// heading "still under the radar", with a bare score beside each.
class RisingCarousel extends ConsumerWidget {
  const RisingCarousel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = FeedKey(
      sort: ToolSort.rising,
      pricing: ref.watch(discoverPricingProvider),
      movingOnly: true,
    );
    final state = ref.watch(toolFeedProvider(key));
    if (state.loading || state.items.isEmpty) {
      return const SizedBox.shrink();
    }
    final width = MediaQuery.sizeOf(context).width;
    final gutter = LizSpacing.gutter(width);
    final twoColumns = !context.isPhone;
    final items = state.items.take(twoColumns ? 6 : 5).toList();

    final rows = [
      for (var i = 0; i < items.length; i++)
        _ChartRow(rank: i + 1, tool: items[i]),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Rising this week',
          subtitle:
              'Biggest jumps in the last seven days, on GitHub, '
              'Hacker News and Liz.',
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: context.liz.surface,
              shape: LizRadius.shape(
                LizRadius.md,
                side: BorderSide(color: context.liz.hairline),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: twoColumns
                  // Intrinsic height so the divider between the columns
                  // matches them at any text size.
                  ? IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _Column(
                              rows: rows.sublist(0, (rows.length + 1) ~/ 2),
                            ),
                          ),
                          VerticalDivider(
                            width: 1,
                            thickness: 1,
                            indent: 6,
                            endIndent: 6,
                            color: context.liz.hairline,
                          ),
                          Expanded(
                            child: _Column(
                              rows: rows.sublist((rows.length + 1) ~/ 2),
                            ),
                          ),
                        ],
                      ),
                    )
                  : _Column(rows: rows),
            ),
          ),
        ),
      ],
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({required this.rows});
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0)
            // Inset past the rank and logo, as grouped lists do.
            Padding(
              padding: const EdgeInsets.only(left: 108),
              child: Divider(height: 1, color: context.liz.hairline),
            ),
          rows[i],
        ],
      ],
    );
  }
}

class _ChartRow extends StatelessWidget {
  const _ChartRow({required this.rank, required this.tool});
  final int rank;
  final Tool tool;

  @override
  Widget build(BuildContext context) => ToolLink(tool: tool, builder: _row);

  Widget _row(BuildContext context, VoidCallback open) {
    final p = context.liz;
    final reason = tool.trendReason;
    return Semantics(
      button: true,
      label:
          'Number $rank, ${tool.name}. ${tool.tagline}'
          '${reason == null ? '' : '. $reason'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: open,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 68),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '$rank',
                    style: LizText.title3.copyWith(
                      color: p.textSecondary,
                      fontFeatures: LizText.tabular,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ToolLogo(tool: tool, size: 40),
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
                      Text(
                        tool.tagline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LizText.subhead.copyWith(
                          color: p.textSecondary,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      if (reason != null) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(Icons.trending_up, size: 14, color: p.rising),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                reason,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: LizText.footnote.copyWith(
                                  color: LizColors.legibleOn(
                                    p.rising,
                                    p.surface,
                                  ),
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: LizText.tabular,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (tool.pricingType != PricingType.unknown) ...[
                  const SizedBox(width: 12),
                  Text(
                    tool.pricingType.label,
                    style: LizText.footnote.copyWith(color: p.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
