import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../core/config/env.dart';
import '../../core/providers.dart';
import '../../core/telemetry/analytics.dart';
import '../../shared/models/tool.dart';
import '../../shared/widgets/badges.dart';
import '../../shared/widgets/rating_stars.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/time_ago.dart';
import '../../shared/widgets/tool_link.dart';
import '../../shared/widgets/tool_logo.dart';
import '../../shared/widgets/top_bar.dart';

final _compareProvider = FutureProvider.autoDispose.family<List<Tool>, String>((
  ref,
  idsCsv,
) async {
  final ids = idsCsv.split(',').where((e) => e.isNotEmpty).toList();
  final tools = await ref.watch(contentRepositoryProvider).compareTools(ids);
  if (tools.length >= 2) {
    Analytics.track('compare', props: {'tools': tools.length});
  }
  return tools;
});

class CompareScreen extends ConsumerWidget {
  const CompareScreen({super.key, required this.toolIds});
  final List<String> toolIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_compareProvider(toolIds.join(',')));
    return Scaffold(
      appBar: const LizTopBar(
        title: 'Compare',
        section: ('Saved', '/saved'),
        // The page's heading is above the table.
        titleIsHeading: false,
        // Comparisons start from Saved; a shared one opened by its address
        // goes back there too.
        fallback: '/saved',
      ),
      body: async.when(
        loading: () => const LoadingView(),
        error: (_, _) => ErrorView(
          onRetry: () => ref.invalidate(_compareProvider(toolIds.join(','))),
        ),
        data: (tools) => tools.length < 2
            // A shared link can outlive the tools in it. Saying "pick some
            // tools" to someone who did pick them, and had one withdrawn since,
            // reads as though the link never worked.
            ? EmptyView(
                icon: Icons.compare_arrows,
                title: tools.length < toolIds.length
                    ? 'Some of these tools are no longer listed'
                    : 'Pick 2–3 tools to compare',
                message: tools.length < toolIds.length
                    ? 'A comparison needs at least two. Pick another from your '
                          'Saved list.'
                    : 'Select tools from your Saved list.',
              )
            : _CompareTable(
                tools: tools,
                // The address already holds the comparison
                // (/compare?ids=…), so a copied link opens the same table
                // for whoever receives it.
                onCopyLink: () {
                  final link =
                      Env.permalink('/compare?ids=${toolIds.join(',')}') ?? '';
                  if (link.isEmpty) return;
                  Clipboard.setData(ClipboardData(text: link));
                  Analytics.track('share', props: {'what': 'compare'});
                  ScaffoldMessenger.of(context)
                    ..clearSnackBars()
                    ..showSnackBar(
                      const SnackBar(content: Text('Link copied')),
                    );
                },
              ),
      ),
    );
  }
}

/// Tools side by side (docs/DESIGN.md §8, Compare). Rows have fixed
/// heights so the attribute labels can stay pinned on a narrow screen while
/// the tool columns scroll beside them — the old table scrolled the labels
/// away with everything else.
class _CompareTable extends StatelessWidget {
  const _CompareTable({required this.tools, required this.onCopyLink});
  final List<Tool> tools;
  final VoidCallback onCopyLink;

  static const _labelWidth = 132.0;
  static const _minColumn = 200.0;
  static const _maxColumn = 300.0;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    final gutter = LizSpacing.gutter(MediaQuery.sizeOf(context).width);

    // The best value in a row is worth pointing out; that is what a
    // comparison is for.
    final bestRating = tools
        .where((t) => t.ratingCount > 0)
        .fold<double>(0, (m, t) => t.avgRating > m ? t.avgRating : m);
    final bestStars = tools.fold<int>(0, (m, t) {
      final stars = t.ghStars ?? 0;
      return stars > m ? stars : m;
    });
    final hasStars = bestStars > 0;

    // A Wrap, not a Row: at the narrowest column, stars, the figure and the
    // "Best" badge do not fit on one line.
    Widget emphasis(String text, bool best) => Wrap(
      spacing: 6,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          text,
          style: LizText.callout.copyWith(
            color: p.textPrimary,
            fontWeight: best ? FontWeight.w700 : FontWeight.w400,
            fontFeatures: LizText.tabular,
          ),
        ),
        if (best && tools.length > 1) LizPill(label: 'Best', color: p.positive),
      ],
    );

    final rows = <_Row>[
      _Row('Pricing', 52, (t) => PricingLabel(t.pricingType)),
      _Row(
        'Price',
        52,
        (t) => Text(
          t.priceNote ?? '—',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: LizText.callout.copyWith(color: p.textPrimary),
        ),
      ),
      _Row(
        'Rating',
        52,
        (t) => t.ratingCount == 0
            ? Text('—', style: LizText.callout.copyWith(color: p.textSecondary))
            : Wrap(
                spacing: 6,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  RatingStars(t.avgRating, size: 14),
                  emphasis(
                    t.avgRating.toStringAsFixed(1),
                    t.avgRating == bestRating,
                  ),
                ],
              ),
      ),
      _Row(
        'Category',
        52,
        (t) => Text(
          categoryLabel(t.category),
          style: LizText.callout.copyWith(color: p.textPrimary),
        ),
      ),
      _Row(
        'Platforms',
        52,
        (t) => Text(
          t.platforms.isEmpty ? '—' : t.platforms.join(', '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: LizText.callout.copyWith(color: p.textPrimary),
        ),
      ),
      // What moved this week, in words. This row used to rank the tools by a
      // score computed from invented totals.
      _Row(
        'This week',
        52,
        (t) => Text(
          t.trendReason ?? 'No change measured',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: LizText.callout.copyWith(
            color: t.trendReason == null ? p.textSecondary : p.textPrimary,
          ),
        ),
      ),
      if (hasStars)
        _Row(
          'GitHub stars',
          52,
          (t) => t.ghStars == null
              ? Text(
                  '—',
                  style: LizText.callout.copyWith(color: p.textSecondary),
                )
              : emphasis(compactCount(t.ghStars!), t.ghStars == bestStars),
        ),
      _Row(
        'First seen',
        52,
        (t) => Text(
          DateFormat('d MMM y').format(t.createdAt.toLocal()),
          style: LizText.callout.copyWith(
            color: p.textPrimary,
            fontFeatures: LizText.tabular,
          ),
        ),
      ),
      _Row(
        'Tags',
        84,
        (t) => Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [for (final tag in t.tags.take(4)) LizPill(label: tag)],
        ),
      ),
    ];

    const headerHeight = 188.0;

    Widget cell(double height, Widget child, {bool first = false}) => Container(
      height: height * scale,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.hairline)),
      ),
      child: child,
    );

    final labels = SizedBox(
      width: _labelWidth,
      child: Column(
        children: [
          SizedBox(height: headerHeight * scale),
          for (final row in rows)
            cell(
              row.height,
              Text(
                row.label,
                style: LizText.subhead.copyWith(color: p.textSecondary),
              ),
            ),
        ],
      ),
    );

    Widget column(Tool t, double width) => SizedBox(
      width: width,
      child: Column(
        children: [
          SizedBox(
            height: headerHeight * scale,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ToolLogo(tool: t, size: 44),
                  const SizedBox(height: 10),
                  Text(
                    t.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LizText.headline.copyWith(color: p.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Expanded(
                    child: Text(
                      t.tagline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: LizText.footnote.copyWith(
                        color: p.textSecondary,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => context.push(toolPath(t)),
                    child: const Text('View tool'),
                  ),
                ],
              ),
            ),
          ),
          for (final row in rows) cell(row.height, row.cell(t)),
        ],
      ),
    );

    final names = tools.map((t) => t.name).toList();
    final subtitle = names.length == 2
        ? '${names[0]} and ${names[1]}, side by side.'
        : '${names.sublist(0, names.length - 1).join(', ')} and '
              '${names.last}, side by side.';
    final phone = context.isPhone;

    final table = LayoutBuilder(
      builder: (context, constraints) {
        final room = constraints.maxWidth - _labelWidth;
        final fits = room / tools.length >= _minColumn;
        if (fits) {
          final width = room / tools.length;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [labels, for (final t in tools) column(t, width)],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            labels,
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [for (final t in tools) column(t, _minColumn)],
                ),
              ),
            ),
          ],
        );
      },
    );

    return SingleChildScrollView(
      child: MaxWidth(
        // As wide as the columns need, so the title lines up with the table.
        maxWidth: _labelWidth + tools.length * _maxColumn + gutter * 2,
        child: Padding(
          padding: EdgeInsets.fromLTRB(gutter, phone ? 8 : 36, gutter, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          container: true,
                          header: true,
                          headingLevel: 1,
                          child: Text(
                            'Compare',
                            style: (phone ? LizText.title1 : LizText.largeTitle)
                                .copyWith(color: p.textPrimary),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: LizText.body.copyWith(color: p.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Tooltip(
                    message: 'Copy link to this comparison',
                    child: OutlinedButton.icon(
                      onPressed: onCopyLink,
                      icon: const Icon(Icons.link, size: 18),
                      label: const Text('Copy link'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              DecoratedBox(
                decoration: ShapeDecoration(
                  color: p.surface,
                  shape: LizRadius.shape(
                    LizRadius.lg,
                    side: BorderSide(color: p.hairline),
                  ),
                ),
                child: ClipRSuperellipse(
                  borderRadius: BorderRadius.circular(LizRadius.lg),
                  child: table,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row {
  const _Row(this.label, this.height, this.cell);
  final String label;
  final double height;
  final Widget Function(Tool) cell;
}
