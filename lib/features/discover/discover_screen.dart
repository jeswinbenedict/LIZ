import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../core/providers.dart';
import '../alerts/alerts_screen.dart';
import '../../shared/models/category.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/pricing_filter.dart';
import '../../shared/widgets/tool_grid_sliver.dart';
import 'discover_controller.dart';
import 'rising_carousel.dart';
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
    if (widget.initialCategory != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(discoverCategoryProvider.notifier).set(widget.initialCategory);
      });
    }
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
    final category = ref.watch(discoverCategoryProvider);
    final pricing = ref.watch(discoverPricingProvider);
    final key = FeedKey(sort: sort, category: category, pricing: pricing);

    final phone = context.isPhone;
    return Scaffold(
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
                    icon: const Icon(Icons.auto_awesome_outlined),
                    onPressed: () => context.go('/ask'),
                  ),
                ],
              ),
            SliverToBoxAdapter(
              child: MaxWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PageHeader(
                      title: 'Discover',
                      subtitle: phone
                          ? null
                          : 'New AI tools, ranked by how fast they are rising.',
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
                    const WelcomeCard(),
                    const RisingCarousel(),
                    const SectionHeader(title: 'All tools'),
                    const _CategoryChips(),
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
    ToolSort.trending: 'Trending',
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
