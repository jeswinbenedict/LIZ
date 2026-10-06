import 'package:flutter/material.dart';
import '../../shared/widgets/liz_mark.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../core/providers.dart';
import '../alerts/alerts_screen.dart';
import '../../shared/models/category.dart';
import '../../shared/widgets/badges.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/page_title.dart';
import '../../shared/widgets/pricing_filter.dart';
import '../../shared/widgets/tool_grid_sliver.dart';
import 'discover_controller.dart';
import 'new_this_week.dart';
import 'tool_headlines.dart';
import 'top_movers.dart';
import 'welcome_card.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key, this.initialCategory});
  final String? initialCategory;

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // People leave a tab open for hours. Coming back to a day-old catalog is
    // the realistic way this feed goes stale, so re-read it on return rather
    // than holding a socket open for changes that arrive once a day.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    final key = FeedKey(
      sort: ref.read(discoverSortProvider),
      category: ref.read(discoverCategoryProvider),
    );
    // The controller decides whether enough time has passed to be worth a
    // round trip, so flicking between tabs does not re-query on every switch.
    ref.read(toolFeedProvider(key).notifier).refreshIfStale();
  }

  @override
  Widget build(BuildContext context) {
    final sort = ref.watch(discoverSortProvider);
    // A category page (/category/<slug>) is this screen narrowed to one
    // kind of tool: its own title and movers, and only its tools. It does not
    // touch Discover's own category filter, so going back finds Discover as
    // it was left.
    final pageCategory = widget.initialCategory;
    final category = pageCategory ?? ref.watch(discoverCategoryProvider);
    final pricing = ref.watch(discoverPricingProvider);
    final key = FeedKey(sort: sort, category: category, pricing: pricing);
    final categoryName = pageCategory == null
        ? null
        : (ref
                  .watch(categoriesProvider)
                  .value
                  ?.where((c) => c.slug == pageCategory)
                  .firstOrNull
                  ?.name ??
              categoryLabel(pageCategory));

    final phone = context.isPhone;
    final screen = Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(toolFeedProvider);
          await ref.read(toolFeedProvider(key).notifier).refresh();
        },
        child: CustomScrollView(
          slivers: [
            if (phone)
              PhoneTopBar(
                actions: [
                  const AlertsBell(),
                  IconButton(
                    tooltip: 'Ask Liz',
                    icon: const LizMark.icon(),
                    onPressed: () => context.go('/ask'),
                  ),
                ],
              ),
            SliverToBoxAdapter(
              child: MaxWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (categoryName != null)
                      PageHeader(
                        eyebrow: '// CATEGORY',
                        title: categoryName,
                        subtitle:
                            'Every $categoryName tool Liz lists, ranked by how '
                            'fast it is growing.',
                        trailing: TextButton.icon(
                          onPressed: () => context.go('/'),
                          icon: const Icon(Icons.arrow_back, size: 18),
                          label: const Text('All of Discover'),
                        ),
                        bottom: 16,
                      )
                    else
                      PageHeader(
                        eyebrow: '// MOMENTUM, NOT HYPE',
                        title: 'Discover',
                        subtitle: phone
                            ? null
                            : 'New AI tools, ranked by how fast they are '
                                  'growing.',
                        // Tablets have no sidebar to carry alerts.
                        trailing: context.isTablet ? const AlertsBell() : null,
                        bottom: 16,
                      ),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: LizSpacing.gutter(
                          MediaQuery.sizeOf(context).width,
                        ),
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 640),
                          child: SearchLauncher(large: !phone),
                        ),
                      ),
                    ),
                    if (categoryName != null) ...[
                      TopMovers(category: pageCategory),
                      SectionHeader(title: 'All $categoryName tools'),
                    ] else ...[
                      const WelcomeCard(),
                      const TopMovers(),
                      const ToolHeadlines(),
                      const ForYou(),
                      NewThisWeek(
                        onSeeAll: () => ref
                            .read(discoverSortProvider.notifier)
                            .set(ToolSort.newest),
                      ),
                      const SectionHeader(title: 'All tools'),
                      const _CategoryChips(),
                    ],
                    const _SortBar(),
                  ],
                ),
              ),
            ),
            MaxWidthSliver(sliver: ToolGridSliver(feedKey: key)),
            LoadMoreFooter(feedKey: key),
          ],
        ),
      ),
    );
    // The same title the prerendered category page carries.
    return categoryName == null
        ? screen
        : PageTitle(title: PageTitle.forCategory(categoryName), child: screen);
  }
}

class _CategoryChips extends ConsumerWidget {
  const _CategoryChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final selected = ref.watch(discoverCategoryProvider);

    return categoriesAsync.when(
      loading: () => const SizedBox(height: 48),
      error: (_, _) => const SizedBox(height: 0),
      data: (categories) => SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(
            horizontal: LizSpacing.gutter(MediaQuery.sizeOf(context).width),
          ),
          children: [
            _chip(
              context,
              ref,
              label: 'All',
              slug: null,
              selected: selected == null,
            ),
            for (final Category c in categories)
              _chip(
                context,
                ref,
                label: c.name,
                slug: c.slug,
                selected: selected == c.slug,
              ),
          ],
        ),
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    WidgetRef ref, {
    required String label,
    required String? slug,
    required bool selected,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: LizFilterPill(
        label: label,
        selected: selected,
        onTap: () => ref.read(discoverCategoryProvider.notifier).set(slug),
      ),
    );
  }
}

class _SortBar extends ConsumerWidget {
  const _SortBar();

  static const _labels = {
    ToolSort.rising: 'Rising',
    ToolSort.newest: 'New',
    ToolSort.topRated: 'Top rated',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(discoverSortProvider);
    final gutter = LizSpacing.gutter(MediaQuery.sizeOf(context).width);
    // One toolbar: how to order, and what it may cost. The sort used to be a
    // second row of chips that looked like more categories.
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 4, gutter, 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          LizSegmented<ToolSort>(
            segments: _labels,
            value: sort,
            onChanged: (value) =>
                ref.read(discoverSortProvider.notifier).set(value),
          ),
          PricingFilter(
            selected: ref.watch(discoverPricingProvider),
            onChanged: (value) =>
                ref.read(discoverPricingProvider.notifier).set(value),
          ),
        ],
      ),
    );
  }
}
