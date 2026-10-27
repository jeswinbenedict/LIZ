import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../shared/widgets/news_card.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/skeletons.dart';
import '../../shared/widgets/states.dart';
import 'news_controller.dart';

/// Technology News Feed — live tech headlines from RSS/API ingestion, updated
/// hourly and pushed in real time via Supabase Realtime.
///
/// A reading column (docs/DESIGN.md §8, News): the title, the outlets as
/// filter pills, then the stories under the day they ran.
class NewsScreen extends ConsumerStatefulWidget {
  const NewsScreen({super.key});

  @override
  ConsumerState<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends ConsumerState<NewsScreen> {
  /// The outlet being read, or null for all of them.
  String? _source;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final state = ref.watch(newsControllerProvider);
    final controller = ref.read(newsControllerProvider.notifier);

    final phone = context.isPhone;
    final gutter = LizSpacing.gutter(MediaQuery.sizeOf(context).width);
    const column = 760.0;

    // The outlets in the feed, busiest first. A filter of one is no filter.
    final counts = <String, int>{};
    for (final item in state.items) {
      final key = item.source ?? '';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final sources = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    final source = sources.contains(_source) ? _source : null;
    final items = source == null
        ? state.items
        : state.items.where((i) => (i.source ?? '') == source).toList();

    // Stories under the day they ran, newest first: a heading row, then its
    // stories, flattened so the list stays lazy.
    final rows = <Object>[];
    String? day;
    for (var i = 0; i < items.length; i++) {
      final heading = newsDay(items[i].publishedAt);
      if (heading != day) {
        rows.add(heading);
        day = heading;
      }
      rows.add(i);
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: CustomScrollView(
          slivers: [
            if (phone) const PhoneTopBar(),
            SliverToBoxAdapter(
              child: MaxWidth(
                maxWidth: column + gutter * 2,
                child: PageHeader(
                  title: 'News',
                  subtitle: phone
                      ? null
                      : 'The day in technology, from the outlets that '
                            'cover it. Updated hourly.',
                  trailing: state.live ? const _LiveStatus() : null,
                  bottom: 16,
                ),
              ),
            ),
            if (sources.length > 1)
              SliverToBoxAdapter(
                child: MaxWidth(
                  maxWidth: column + gutter * 2,
                  child: _SourcePills(
                    sources: sources,
                    selected: source,
                    gutter: gutter,
                    onSelect: (s) => setState(() => _source = s),
                  ),
                ),
              ),
            if (state.loading)
              const NewsListSkeletonSliver()
            else if (state.error != null && state.items.isEmpty)
              SliverToBoxAdapter(child: ErrorView(onRetry: controller.refresh))
            else if (state.items.isEmpty)
              const SliverToBoxAdapter(
                child: EmptyView(
                  icon: Icons.newspaper_outlined,
                  title: 'No news yet',
                  message:
                      'The feed fills up as the ingestion job pulls the latest tech headlines.',
                ),
              )
            else
              MaxWidthSliver(
                maxWidth: column + gutter * 2,
                sliver: SliverPadding(
                  padding: EdgeInsets.fromLTRB(gutter - 4, 0, gutter - 4, 32),
                  sliver: SliverList.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, r) {
                      final row = rows[r];
                      if (row is String) return _DayHeading(row, first: r == 0);
                      final i = row as int;
                      if (i >= items.length - 3) {
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => controller.loadMore(),
                        );
                      }
                      // A rule between stories of the same day; the day's
                      // heading separates the rest.
                      final first = r > 0 && rows[r - 1] is String;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!first)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Divider(height: 1, color: p.hairline),
                            ),
                          NewsCard(item: items[i], lead: i == 0),
                        ],
                      );
                    },
                  ),
                ),
              ),
            if (state.loadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Which day a story sits under: today, yesterday, the last week, or before.
String newsDay(DateTime at, {DateTime? now}) {
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final day = DateUtils.dateOnly(at.toLocal());
  final ago = today.difference(day).inDays;
  if (ago <= 0) return 'Today';
  if (ago == 1) return 'Yesterday';
  if (ago < 7) return 'This week';
  return 'Earlier';
}

/// A day's name above its stories, with a hairline under it.
class _DayHeading extends StatelessWidget {
  const _DayHeading(this.text, {required this.first});
  final String text;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Padding(
      padding: EdgeInsets.fromLTRB(4, first ? 16 : 28, 4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            header: true,
            child: Text(
              text,
              style: LizText.headline.copyWith(color: p.textPrimary),
            ),
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: p.hairlineStrong),
        ],
      ),
    );
  }
}

/// "All" and each outlet in the feed. One line that scrolls sideways on a
/// phone, wrapping lines on a wider window.
class _SourcePills extends StatelessWidget {
  const _SourcePills({
    required this.sources,
    required this.selected,
    required this.gutter,
    required this.onSelect,
  });
  final List<String> sources;
  final String? selected;
  final double gutter;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final pills = [
      LizFilterPill(
        label: 'All',
        selected: selected == null,
        onTap: () => onSelect(null),
      ),
      for (final s in sources)
        LizFilterPill(
          label: newsSourceLabel(s),
          selected: selected == s,
          onTap: () => onSelect(selected == s ? null : s),
        ),
    ];
    if (context.isPhone) {
      return SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: gutter),
          itemCount: pills.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) => Center(child: pills[i]),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 12),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(spacing: 8, runSpacing: 8, children: pills),
      ),
    );
  }
}

/// The feed is connected and new stories arrive on their own: a green dot
/// and a word, no fill.
class _LiveStatus extends StatelessWidget {
  const _LiveStatus();

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Semantics(
      label: 'Live: new stories appear as they arrive',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: p.positive,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Live',
              style: LizText.subhead.copyWith(color: p.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
